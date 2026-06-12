#!/usr/bin/env bash
# Tests for prism-launch: prepare validation/rendering + parallax --dry-run.
# No network — never invokes a real peer. Run: ./test-prism-launch.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LAUNCH="$HERE/prism-launch"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/prism-launch-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL: $1"; }

# expect_ok <desc> <cmd...>   — command must exit 0
expect_ok()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d (expected success)"; fi; }
# expect_err <desc> <cmd...>  — command must exit non-zero
expect_err() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d (expected failure)"; else ok "$d"; fi; }

make_packet() {
  cat > "$1" <<'PKT'
## Full Question
Design something.

## Context
Some context.

## Constraints
You are a read-only leaf node.
PKT
}

echo "== prepare: happy path =="
PKT="$TMP/prism-run1.md"; make_packet "$PKT"
CFG="$TMP/run1-config.json"
cat > "$CFG" <<JSON
{
  "shared_packet": "$PKT",
  "parallax": [
    {"to":"codex","name":"temporal","effort":"medium","lens":"Temporal","lens_desc":"weigh clean extension"},
    {"to":"deepseek","name":"first-principles","lens":"First-Principles","lens_desc":"reason from fundamentals"},
    {"to":"mimo","name":"outsider","lens":"Outsider","lens_desc":"weigh a newcomer view"}
  ],
  "subagents": [
    {"lens":"Simplicity","lens_desc":"weigh fewest moving parts"},
    {"lens":"Adversarial","lens_desc":"weigh failure modes"}
  ]
}
JSON
expect_ok "prepare succeeds on a valid config" "$LAUNCH" prepare --config "$CFG"

MAN="$TMP/prism-run1-manifest.json"
[ -f "$MAN" ] && ok "manifest written" || bad "manifest written"
[ "$(jq -r '.counts.subagents' "$MAN" 2>/dev/null)" = "2" ] && ok "subagent count = 2" || bad "subagent count = 2"
[ "$(jq -r '.counts.by_peer.codex' "$MAN" 2>/dev/null)" = "1" ] && ok "codex count = 1" || bad "codex count = 1"
[ "$(jq -r '.counts.by_peer.deepseek' "$MAN" 2>/dev/null)" = "1" ] && ok "deepseek count = 1" || bad "deepseek count = 1"
[ "$(jq -r '.counts.by_peer.mimo' "$MAN" 2>/dev/null)" = "1" ] && ok "mimo count = 1" || bad "mimo count = 1"
[ "$(jq -r '.counts.dispatched_total' "$MAN" 2>/dev/null)" = "5" ] && ok "dispatched_total = 5" || bad "dispatched_total = 5"
[ "$(jq -r '.parallax[0].name' "$MAN" 2>/dev/null)" = "prism-temporal" ] && ok "relay name prefixed with prism-" || bad "relay name prefixed with prism-"
[ "$(jq -r '.parallax[1].effort' "$MAN" 2>/dev/null)" = "null" ] && ok "deepseek effort is null" || bad "deepseek effort is null"
[ "$(jq -r '.parallax[0].effort' "$MAN" 2>/dev/null)" = "medium" ] && ok "codex effort = medium" || bad "codex effort = medium"
[ "$(jq -r '.parallax[0].template' "$MAN" 2>/dev/null)" = "codex" ] && ok "codex uses codex template (registry)" || bad "codex template = codex"
[ "$(jq -r '.parallax[1].template' "$MAN" 2>/dev/null)" = "costar" ] && ok "deepseek uses shared costar template (registry)" || bad "deepseek template = costar"
case "$(jq -r '.parallax[0].log' "$MAN" 2>/dev/null)" in *-out-prism-temporal.log) ok "manifest log path matches runtime (prism- prefixed)" ;; *) bad "manifest log path prism- prefixed" ;; esac

echo "== prepare: launcher rendering =="
CXL=$(jq -r '.parallax[0].launcher' "$MAN")
[ -f "$CXL" ] && ok "codex launcher file rendered" || bad "codex launcher file rendered"
head -1 "$CXL" | grep -q '^CRITICAL:' && ok "launcher starts with anti-recursion CRITICAL line" || bad "launcher CRITICAL line"
! grep -q '{{' "$CXL" && ok "no surviving {{slots}} in launcher" || bad "no surviving {{slots}}"
grep -qF "$PKT" "$CXL" && ok "shared_packet path substituted into launcher" || bad "packet path substituted"
grep -q 'Temporal' "$CXL" && ok "lens name substituted into launcher" || bad "lens name substituted"
# Template-by-style: codex renders <goal>, costar peers render <objective>.
DSL=$(jq -r '.parallax[1].launcher' "$MAN")
grep -q '<goal>' "$CXL" && ok "codex launcher uses <goal> scaffolding" || bad "codex <goal> scaffolding"
grep -q '<objective>' "$DSL" && ok "costar launcher uses <objective> scaffolding" || bad "costar <objective> scaffolding"
SAL=$(jq -r '.subagents[0].launcher' "$MAN")
[ -f "$SAL" ] && ok "subagent launcher file rendered" || bad "subagent launcher file rendered"
echo "$SAL" | grep -q 'launcher-subagent-simplicity.md' && ok "subagent lens slugified into filename" || bad "subagent slug filename"

echo "== prepare + dry-run: a 3-peer subset (mixed-tier guard; legacy — not the N=1 default) =="
PKT4="$TMP/prism-run4.md"; make_packet "$PKT4"
CFG4="$TMP/run4-config.json"
jq -n --arg p "$PKT4" '{shared_packet:$p,parallax:[{to:"codex",name:"a",effort:"medium",lens:"Adversarial",lens_desc:"d1"},{to:"deepseek",name:"b",lens:"Completeness",lens_desc:"d2"},{to:"mimo",name:"c",lens:"Consistency",lens_desc:"d3"}],subagents:[{lens:"Correctness",lens_desc:"d5"}]}' > "$CFG4"
expect_ok "prepare accepts all three parallax tiers together" "$LAUNCH" prepare --config "$CFG4"
MAN4="$TMP/prism-run4-manifest.json"
[ "$(jq -r '.counts.parallax_total' "$MAN4" 2>/dev/null)" = "3" ] && ok "three-tier counts: parallax_total=3" || bad "three-tier counts"
DRY4=$("$LAUNCH" parallax "$MAN4" --dry-run 2>/dev/null)
[ "$(echo "$DRY4" | grep -c 'relay call --to')" = "3" ] && ok "three-tier dry-run lists exactly 3 relay calls" || bad "three-tier dry-run lists 3 relay calls"

echo "== prepare: default five-tier shape + canonical display order =="
PKT5="$TMP/prism-run5.md"; make_packet "$PKT5"
CFG5="$TMP/run5-config.json"
# tiers deliberately scrambled in the config; the dispatch-shape display must still be canonical
jq -n --arg p "$PKT5" '{shared_packet:$p,parallax:[{to:"mimo",name:"a",lens:"L1",lens_desc:"d"},{to:"codex",name:"b",effort:"medium",lens:"L2",lens_desc:"d"},{to:"deepseek",name:"c",lens:"L3",lens_desc:"d"},{to:"grok-composer",name:"d",lens:"L4",lens_desc:"d"},{to:"grok-build",name:"e",effort:"high",lens:"L5",lens_desc:"d"}],subagents:[{lens:"L6",lens_desc:"d"}]}' > "$CFG5"
OUT5=$("$LAUNCH" prepare --config "$CFG5" 2>/dev/null)
MAN5="$TMP/prism-run5-manifest.json"
[ "$(jq -r '.counts.parallax_total' "$MAN5" 2>/dev/null)" = "5" ] && ok "default five-tier counts: parallax_total=5" || bad "five-tier counts"
echo "$OUT5" | grep -q 'dispatch shape: subagents=1 codex=1 grok-build=1 grok-composer=1 deepseek=1 mimo=1' && ok "dispatch shape printed in canonical order (not alphabetical)" || bad "dispatch shape canonical order"

echo "== prepare + dry-run: grok parallax tiers (effort vs no-knob) =="
PKTG="$TMP/prism-grok.md"; make_packet "$PKTG"
# grok-build (effort high) + grok-composer (no effort) accepted together
CFGG="$TMP/grok-config.json"
jq -n --arg p "$PKTG" '{shared_packet:$p,parallax:[{to:"grok-build",name:"gb",effort:"high",lens:"Adversarial",lens_desc:"d1"},{to:"grok-composer",name:"gc",lens:"Outsider",lens_desc:"d2"}],subagents:[]}' > "$CFGG"
expect_ok "prepare accepts grok-build (effort high) + grok-composer (no effort)" "$LAUNCH" prepare --config "$CFGG"
MANG="$TMP/prism-grok-manifest.json"
[ "$(jq -r '.parallax[0].effort' "$MANG" 2>/dev/null)" = "high" ] && ok "grok-build effort = high" || bad "grok-build effort = high"
[ "$(jq -r '.parallax[0].template' "$MANG" 2>/dev/null)" = "costar" ] && ok "grok-build uses costar template (registry)" || bad "grok-build template = costar"
[ "$(jq -r '.counts.by_peer."grok-build"' "$MANG" 2>/dev/null)" = "1" ] && ok "grok-build count = 1" || bad "grok-build count = 1"
[ "$(jq -r '.parallax[1].effort' "$MANG" 2>/dev/null)" = "null" ] && ok "grok-composer effort is null" || bad "grok-composer effort is null"
[ "$(jq -r '.parallax[1].template' "$MANG" 2>/dev/null)" = "costar" ] && ok "grok-composer uses costar template (registry)" || bad "grok-composer template = costar"
[ "$(jq -r '.counts.by_peer."grok-composer"' "$MANG" 2>/dev/null)" = "1" ] && ok "grok-composer count = 1" || bad "grok-composer count = 1"

# grok-build effort_values are medium/high only — reject both xhigh (Codex's word) and low (dropped from the registry)
CGE="$TMP/grok-badeffort.json"; jq -n --arg p "$PKTG" '{shared_packet:$p,parallax:[{to:"grok-build",name:"x",effort:"xhigh",lens:"L",lens_desc:"d"}],subagents:[]}' > "$CGE"
expect_err "rejects invalid grok-build effort (xhigh)" "$LAUNCH" prepare --config "$CGE"
CGL="$TMP/grok-loweffort.json"; jq -n --arg p "$PKTG" '{shared_packet:$p,parallax:[{to:"grok-build",name:"x",effort:"low",lens:"L",lens_desc:"d"}],subagents:[]}' > "$CGL"
expect_err "rejects invalid grok-build effort (low — no longer in registry)" "$LAUNCH" prepare --config "$CGL"

# grok-composer rejects ANY effort (it has no effort_values)
CGC="$TMP/grok-composer-effort.json"; jq -n --arg p "$PKTG" '{shared_packet:$p,parallax:[{to:"grok-composer",name:"x",effort:"high",lens:"L",lens_desc:"d"}],subagents:[]}' > "$CGC"
expect_err "rejects --effort on grok-composer (no knob)" "$LAUNCH" prepare --config "$CGC"

# dry-run: grok-build carries --effort high; grok-composer carries no --effort.
# The rejection cases above re-ran prepare on the same packet, which clears prior
# artifacts (one packet = one run) — regenerate the valid manifest first.
"$LAUNCH" prepare --config "$CFGG" >/dev/null 2>&1
DRYG=$("$LAUNCH" parallax "$MANG" --dry-run 2>/dev/null)
echo "$DRYG" | grep -q 'relay call --to grok-build --name prism-gb --effort high' && ok "grok-build dry-run cmd has --effort high" || bad "grok-build dry-run --effort high"
echo "$DRYG" | grep -q 'relay call --to grok-composer --name prism-gc <' && ok "grok-composer dry-run cmd has no --effort" || bad "grok-composer dry-run no --effort"

echo "== prepare: negative cases (fail-closed) =="
# missing a still-required section (## Context) → fail-closed
P2="$TMP/p2.md"; printf '## Full Question\nq\n' > "$P2"
C2="$TMP/c2.json"; jq -n --arg p "$P2" '{shared_packet:$p,parallax:[],subagents:[{lens:"X",lens_desc:"y"}]}' > "$C2"
expect_err "rejects packet missing a required section (## Context)" "$LAUNCH" prepare --config "$C2"

# missing ## Constraints → prepare INJECTS the canonical block (not a failure)
P2c="$TMP/p2c.md"; printf '## Full Question\nq\n\n## Context\nc\n' > "$P2c"
C2c="$TMP/c2c.json"; jq -n --arg p "$P2c" '{shared_packet:$p,parallax:[],subagents:[{lens:"Xc",lens_desc:"y"}]}' > "$C2c"
expect_ok "injects canonical Constraints when the packet omits them" "$LAUNCH" prepare --config "$C2c"
{ grep -q '^## Constraints' "$P2c" && grep -q 'read-only leaf node' "$P2c"; } && ok "packet gained the verbatim Constraints" || bad "Constraints not injected into packet"
# idempotent: re-running prepare must not double-inject
"$LAUNCH" prepare --config "$C2c" >/dev/null 2>&1
[ "$(grep -c '^## Constraints' "$P2c")" = "1" ] && ok "Constraints injection is idempotent (no double on re-run)" || bad "Constraints double-injected on re-run"
# How-to-answer block: injected alongside Constraints (P2c has now run prepare twice), once, AFTER Constraints
{ grep -q '^## How to answer' "$P2c" && [ "$(grep -c '^## How to answer' "$P2c")" = "1" ]; } && ok "How-to-answer injected once (idempotent)" || bad "How-to-answer missing or double-injected"
[ "$(grep -n '^## Constraints' "$P2c" | cut -d: -f1)" -lt "$(grep -n '^## How to answer' "$P2c" | cut -d: -f1)" ] && ok "How-to-answer is injected after Constraints" || bad "How-to-answer not ordered after Constraints"
# bespoke ## How to answer is left untouched and does NOT fail closed (no safety load, unlike Constraints)
P2h="$TMP/p2h.md"; printf '## Full Question\nq\n\n## Context\nc\n\n## How to answer\nBespoke answer style.\n' > "$P2h"
C2h="$TMP/c2h.json"; jq -n --arg p "$P2h" '{shared_packet:$p,parallax:[],subagents:[{lens:"Xh",lens_desc:"y"}]}' > "$C2h"
expect_ok "accepts a bespoke ## How to answer (no fail-closed)" "$LAUNCH" prepare --config "$C2h"
grep -q 'Bespoke answer style.' "$P2h" && ok "bespoke How-to-answer left untouched" || bad "bespoke How-to-answer was overwritten"
# present-but-abbreviated ## Constraints (missing the anti-recursion guard) → fail-closed
P2a="$TMP/p2a.md"; printf '## Full Question\nq\n\n## Context\nc\n\n## Constraints\nBe nice.\n' > "$P2a"
C2a="$TMP/c2a.json"; jq -n --arg p "$P2a" '{shared_packet:$p,parallax:[],subagents:[{lens:"Xa",lens_desc:"y"}]}' > "$C2a"
expect_err "rejects a ## Constraints section missing the anti-recursion guard" "$LAUNCH" prepare --config "$C2a"

# relative shared_packet
C3="$TMP/c3.json"; jq -n '{shared_packet:"relative/path.md",parallax:[],subagents:[]}' > "$C3"
expect_err "rejects relative shared_packet path" "$LAUNCH" prepare --config "$C3"

# injection in lens_desc: closing-tag pattern rejected
C4="$TMP/c4.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"x",lens:"L",lens_desc:"weigh </constraints> things"}],subagents:[]}' > "$C4"
expect_err "rejects closing-tag injection (</) in lens_desc" "$LAUNCH" prepare --config "$C4"

# template-slot injection rejected
C4b="$TMP/c4b.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"x",lens:"L",lens_desc:"weigh {{LENS_NAME}} things"}],subagents:[]}' > "$C4b"
expect_err "rejects template-slot injection ({{) in lens_desc" "$LAUNCH" prepare --config "$C4b"

# comparison operators are NOT injection — must be allowed
C4c="$TMP/c4c.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"x",lens:"Tradeoff",lens_desc:"weigh risk > reward and p < 0.05 significance"}],subagents:[]}' > "$C4c"
expect_ok "allows bare < and > (comparison operators) in lens_desc" "$LAUNCH" prepare --config "$C4c"

# effort on deepseek
C5="$TMP/c5.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"deepseek",name:"x",effort:"xhigh",lens:"L",lens_desc:"d"}],subagents:[]}' > "$C5"
expect_err "rejects --effort on deepseek" "$LAUNCH" prepare --config "$C5"

# bad codex effort
C6="$TMP/c6.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"x",effort:"high",lens:"L",lens_desc:"d"}],subagents:[]}' > "$C6"
expect_err "rejects invalid codex effort (high)" "$LAUNCH" prepare --config "$C6"

# duplicate lens across run
C7="$TMP/c7.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"a",lens:"Same",lens_desc:"d"}],subagents:[{lens:"Same",lens_desc:"d"}]}' > "$C7"
expect_err "rejects duplicate lens name across run" "$LAUNCH" prepare --config "$C7"

# bad name slug (uppercase)
C8="$TMP/c8.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"BadName",lens:"L",lens_desc:"d"}],subagents:[]}' > "$C8"
expect_err "rejects non-slug relay name" "$LAUNCH" prepare --config "$C8"

# bad peer
C9="$TMP/c9.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"gemini",name:"x",lens:"L",lens_desc:"d"}],subagents:[]}' > "$C9"
expect_err "rejects unknown peer (gemini)" "$LAUNCH" prepare --config "$C9"

# duplicate parallax name (distinct lenses) — collides the per-peer log
C10="$TMP/c10.json"; jq -n --arg p "$PKT" '{shared_packet:$p,parallax:[{to:"codex",name:"dup",lens:"A",lens_desc:"d"},{to:"deepseek",name:"dup",lens:"B",lens_desc:"d"}],subagents:[]}' > "$C10"
expect_err "rejects duplicate parallax name" "$LAUNCH" prepare --config "$C10"

# shared_packet path with a space — breaks space-joined log indexing
PSPACE="$TMP/has space.md"; make_packet "$PSPACE"
C11="$TMP/c11.json"; jq -n --arg p "$PSPACE" '{shared_packet:$p,parallax:[{to:"codex",name:"x",lens:"L",lens_desc:"d"}],subagents:[]}' > "$C11"
expect_err "rejects shared_packet path containing whitespace" "$LAUNCH" prepare --config "$C11"

echo "== parallax: --dry-run (no network) =="
# Re-prepare: earlier expect_ok cases reuse $PKT, and prepare clears prior
# artifacts on the same packet (one packet = one run), so regenerate run1's manifest.
"$LAUNCH" prepare --config "$CFG" >/dev/null 2>&1
DRY=$("$LAUNCH" parallax "$MAN" --dry-run 2>/dev/null)
echo "$DRY" | grep -q 'DRY RUN' && ok "dry-run announces itself" || bad "dry-run announces itself"
[ "$(echo "$DRY" | grep -c 'relay call --to')" = "3" ] && ok "dry-run lists exactly 3 relay calls" || bad "dry-run lists 3 relay calls"
echo "$DRY" | grep -q 'relay call --to codex --name prism-temporal --effort medium' && ok "codex dry-run cmd has --effort medium" || bad "codex dry-run --effort"
echo "$DRY" | grep -q 'relay call --to deepseek --name prism-first-principles <' && ok "deepseek dry-run cmd has no --effort" || bad "deepseek dry-run no --effort"
[ -f "$TMP/prism-run1-result.json" ] && bad "dry-run must NOT write a result file" || ok "dry-run writes no result file"

echo "== prepare --dispatch: happy path (line-oriented front-end) =="
PKTD="$TMP/prism-rund.md"; make_packet "$PKTD"
DISP="$TMP/prism-rund.dispatch"
cat > "$DISP" <<DSP
Shared-Packet: $PKTD

# a comment line, ignored
Type: parallax
To: codex
Name: adversarial
Effort: x
Lens: Adversarial
Lens-Desc: weigh the "strongest" attacks: braces {x} and < > are fine

Type: parallax
To: deepseek
Lens: First-Principles
Lens-Desc: reason from fundamentals

Type: subagent
Lens: Simplicity
Lens-Desc: weigh fewest moving parts
DSP
expect_ok "prepare --dispatch succeeds" "$LAUNCH" prepare --dispatch "$DISP"
MAND="$TMP/prism-rund-manifest.json"
[ -f "$MAND" ] && ok "dispatch: manifest written" || bad "dispatch: manifest written"
[ -f "$TMP/prism-rund-config.normalized.json" ] && ok "dispatch: normalized config written for audit" || bad "dispatch: normalized config written"
jq -e '.parallax[0].lens == "Adversarial" and .subagents[0].lens == "Simplicity"' "$TMP/prism-rund-config.normalized.json" >/dev/null 2>&1 && ok "dispatch: normalized config has expected shape" || bad "dispatch: normalized config shape"
[ "$(jq -r '.counts.dispatched_total' "$MAND" 2>/dev/null)" = "3" ] && ok "dispatch: dispatched_total = 3" || bad "dispatch: dispatched_total = 3"
[ "$(jq -r '.parallax[0].effort' "$MAND" 2>/dev/null)" = "xhigh" ] && ok "dispatch: Effort 'x' normalized to xhigh" || bad "dispatch: Effort x -> xhigh"
[ "$(jq -r '.parallax[0].name' "$MAND" 2>/dev/null)" = "prism-adversarial" ] && ok "dispatch: explicit Name used" || bad "dispatch: explicit Name used"
[ "$(jq -r '.parallax[1].name' "$MAND" 2>/dev/null)" = "prism-first-principles" ] && ok "dispatch: Name derived from Lens when omitted" || bad "dispatch: Name derived from Lens"
[ "$(jq -r '.parallax[1].effort' "$MAND" 2>/dev/null)" = "null" ] && ok "dispatch: deepseek effort null" || bad "dispatch: deepseek effort null"
DLAUNCH=$(jq -r '.parallax[0].launcher' "$MAND")
grep -qF 'braces {x} and < > are fine' "$DLAUNCH" && ok "dispatch: quote/brace/colon desc rendered verbatim (no escaping)" || bad "dispatch: desc rendered verbatim"

echo "== prepare --dispatch: negative cases (fail-closed) =="
expect_err "rejects --config and --dispatch together" "$LAUNCH" prepare --config "$CFG" --dispatch "$DISP"

DNP="$TMP/dnp.dispatch"; printf 'Type: subagent\nLens: X\nLens-Desc: y\n' > "$DNP"
expect_err "rejects dispatch missing Shared-Packet" "$LAUNCH" prepare --dispatch "$DNP"

DUK="$TMP/duk.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nModel: codex\nLens: X\nLens-Desc: y\n' "$PKTD" > "$DUK"
expect_err "rejects dispatch unknown key" "$LAUNCH" prepare --dispatch "$DUK"

DBT="$TMP/dbt.dispatch"; printf 'Shared-Packet: %s\n\nTo: codex\nType: parallax\nLens: X\nLens-Desc: y\n' "$PKTD" > "$DBT"
expect_err "rejects dispatch key before any Type record" "$LAUNCH" prepare --dispatch "$DBT"

DED="$TMP/ded.dispatch"; printf 'Shared-Packet: %s\n\nType: parallax\nTo: deepseek\nEffort: x\nLens: X\nLens-Desc: y\n' "$PKTD" > "$DED"
expect_err "rejects dispatch Effort on deepseek (downstream guard)" "$LAUNCH" prepare --dispatch "$DED"

DRP="$TMP/drp.dispatch"; printf 'Shared-Packet: relative/path.md\n\nType: subagent\nLens: X\nLens-Desc: y\n' > "$DRP"
expect_err "rejects dispatch relative Shared-Packet" "$LAUNCH" prepare --dispatch "$DRP"

# distinct lens names that slugify identically — caught by the new subagent-slug guard
DSC="$TMP/dsc.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nLens: First Principles\nLens-Desc: a\n\nType: subagent\nLens: First-Principles\nLens-Desc: b\n' "$PKTD" > "$DSC"
expect_err "rejects subagent lens slug collision" "$LAUNCH" prepare --dispatch "$DSC"

echo "== prepare --dispatch: hardening from review (fail-closed + parity) =="
# duplicate key within one record must fail closed (silent last-wins overwrite otherwise)
DDK="$TMP/ddk.dispatch"; printf 'Shared-Packet: %s\n\nType: parallax\nTo: codex\nLens: A\nLens: B\nLens-Desc: d\n' "$PKTD" > "$DDK"
expect_err "rejects duplicate key within one record" "$LAUNCH" prepare --dispatch "$DDK"

# parallax-only keys on a subagent record (silent wrong-dispatch otherwise)
DST="$TMP/dst.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nTo: codex\nLens: X\nLens-Desc: y\n' "$PKTD" > "$DST"
expect_err "rejects To/Name/Effort on a subagent record" "$LAUNCH" prepare --dispatch "$DST"

# all-whitespace Lens-Desc via dispatch (trim -> empty -> rejected)
DWS="$TMP/dws.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nLens: X\nLens-Desc:    \n' "$PKTD" > "$DWS"
expect_err "rejects all-whitespace Lens-Desc (dispatch)" "$LAUNCH" prepare --dispatch "$DWS"

# parity: all-whitespace lens_desc via --config must now also be rejected
CWS="$TMP/cws.json"; jq -n --arg p "$PKTD" '{shared_packet:$p,parallax:[],subagents:[{lens:"X",lens_desc:"   "}]}' > "$CWS"
expect_err "rejects all-whitespace lens_desc (--config parity)" "$LAUNCH" prepare --config "$CWS"

# subagent lens that slugifies to the empty string -> degenerate filename
DES="$TMP/des.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nLens: !!!\nLens-Desc: y\n' "$PKTD" > "$DES"
expect_err "rejects subagent lens that slugifies to empty" "$LAUNCH" prepare --dispatch "$DES"

# injection guard must not be bypassable via the dispatch path
DIN="$TMP/din.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nLens: X\nLens-Desc: discuss the {{SLOT}} marker\n' "$PKTD" > "$DIN"
expect_err "injection guard ({{) not bypassable via dispatch" "$LAUNCH" prepare --dispatch "$DIN"

echo "== prepare --dispatch: positive coverage (effort case, empty accumulator) =="
# uppercase Effort normalizes (case-insensitive)
PKTE="$TMP/prism-rune.md"; make_packet "$PKTE"
DEF="$TMP/def.dispatch"; printf 'Shared-Packet: %s\n\nType: parallax\nTo: codex\nEffort: X\nLens: Adversarial\nLens-Desc: d\n' "$PKTE" > "$DEF"
expect_ok "accepts uppercase Effort (case-insensitive)" "$LAUNCH" prepare --dispatch "$DEF"
[ "$(jq -r '.parallax[0].effort' "$TMP/prism-rune-manifest.json" 2>/dev/null)" = "xhigh" ] && ok "dispatch: 'Effort: X' normalized to xhigh" || bad "dispatch: Effort X -> xhigh"

# subagents-only dispatch exercises the empty-parallax accumulator ([], not an error)
PKTZ="$TMP/prism-runz.md"; make_packet "$PKTZ"
DZ="$TMP/dz.dispatch"; printf 'Shared-Packet: %s\n\nType: subagent\nLens: Simplicity\nLens-Desc: fewest parts\n' "$PKTZ" > "$DZ"
expect_ok "accepts a subagents-only dispatch (empty parallax accumulator)" "$LAUNCH" prepare --dispatch "$DZ"
[ "$(jq -r '.counts.parallax_total' "$TMP/prism-runz-manifest.json" 2>/dev/null)" = "0" ] && ok "dispatch: empty parallax accumulator -> parallax_total 0" || bad "dispatch: empty parallax -> 0"

echo "== scaffold: symmetric dispatch skeleton =="
SC=$("$LAUNCH" scaffold --n 1 --effort m --packet /tmp/prism-sc.md)
[ "$(printf '%s\n' "$SC" | grep -c '^Type:')" = "6" ] && ok "scaffold --n 1 emits 6 records" || bad "scaffold n=1 record count"
printf '%s\n' "$SC" | grep -q '^Shared-Packet: /tmp/prism-sc.md' && ok "scaffold honors --packet" || bad "scaffold --packet"
printf '%s\n' "$SC" | grep -q '^To: codex'    && printf '%s\n' "$SC" | grep -q '^To: mimo' && ok "scaffold lists all five parallax tiers" || bad "scaffold tiers"
SCX=$("$LAUNCH" scaffold --n 2 --effort xh)
[ "$(printf '%s\n' "$SCX" | grep -c '^Type:')" = "12" ] && ok "scaffold --n 2 emits 12 records" || bad "scaffold n=2 record count"
[ "$(printf '%s\n' "$SCX" | grep -c '^Effort: x')" = "2" ] && [ "$(printf '%s\n' "$SCX" | grep -c '^Effort: h')" = "2" ] && ok "scaffold --effort xh -> codex x, grok-build h" || bad "scaffold xh effort mapping"
expect_err "scaffold rejects a bad --effort" "$LAUNCH" scaffold --effort high2
# a filled scaffold round-trips through prepare
make_packet /tmp/prism-scrt.md
"$LAUNCH" scaffold --n 1 --effort m --packet /tmp/prism-scrt.md \
  | sed 's/^Lens: FILL-1$/Lens: L1/;s/^Lens: FILL-2$/Lens: L2/;s/^Lens: FILL-3$/Lens: L3/;s/^Lens: FILL-4$/Lens: L4/;s/^Lens: FILL-5$/Lens: L5/;s/^Lens: FILL-6$/Lens: L6/;s/^Lens-Desc: FILL$/Lens-Desc: weigh it/' > /tmp/prism-scrt.dispatch
expect_ok "a filled scaffold round-trips through prepare" "$LAUNCH" prepare --dispatch /tmp/prism-scrt.dispatch
# a half-filled scaffold (leftover FILL-<n> lens) must be rejected, not dispatched
make_packet /tmp/prism-schalf.md
"$LAUNCH" scaffold --n 1 --effort m --packet /tmp/prism-schalf.md \
  | sed 's/^Lens-Desc: FILL$/Lens-Desc: weigh it/' > /tmp/prism-schalf.dispatch   # descs filled, lens names left as FILL-<n>
expect_err "prepare rejects a half-filled scaffold (leftover FILL placeholder)" "$LAUNCH" prepare --dispatch /tmp/prism-schalf.dispatch
rm -f /tmp/prism-sc* /tmp/prism-scrt* /tmp/prism-schalf*

echo "== clean: removes run artifacts, refuses unsafe targets =="
touch /tmp/prism-cleantest.md /tmp/prism-cleantest-manifest.json /tmp/prism-cleantest-launcher-x.md
"$LAUNCH" clean /tmp/prism-cleantest.md >/dev/null
[ ! -e /tmp/prism-cleantest.md ] && [ ! -e /tmp/prism-cleantest-manifest.json ] && ok "clean removes /tmp/prism-<id>* by packet path" || bad "clean by path"
touch /tmp/prism-cleanid-manifest.json
"$LAUNCH" clean cleanid >/dev/null
[ ! -e /tmp/prism-cleanid-manifest.json ] && ok "clean removes by bare run id" || bad "clean by id"
expect_err "clean refuses an empty/whole-prefix target" "$LAUNCH" clean prism-
expect_err "clean requires a target" "$LAUNCH" clean
# safety: glob / .. / slash in the target must be refused BEFORE any rm (the blocker)
SENTINEL=/tmp/prism-DONOTDELETE-sentinel.md; touch "$SENTINEL"
expect_err "clean refuses a glob target ('*')"      "$LAUNCH" clean '*'
expect_err "clean refuses a glob target ('a*')"     "$LAUNCH" clean 'a*'
expect_err "clean refuses a '..' traversal target"  "$LAUNCH" clean '/tmp/prism-../../etc/x.md'
expect_err "clean refuses a '/' in the run id"      "$LAUNCH" clean 'foo/bar'
[ -e "$SENTINEL" ] && ok "clean left unrelated /tmp/prism-* files intact" || bad "clean glob-injection wiped sentinel"; rm -f "$SENTINEL"
# a manifest path is stripped to the run base, not a partial clean
touch /tmp/prism-mtest.md /tmp/prism-mtest-manifest.json /tmp/prism-mtest-launcher-x.md
"$LAUNCH" clean /tmp/prism-mtest-manifest.json >/dev/null
[ ! -e /tmp/prism-mtest.md ] && [ ! -e /tmp/prism-mtest-launcher-x.md ] && ok "clean by manifest path strips suffix and clears the whole run" || bad "clean manifest-path partial clean"; rm -f /tmp/prism-mtest*

echo "== scaffold --preset: pre-filled, dispatchable lenses =="
SCP=$("$LAUNCH" scaffold --preset review --packet /tmp/prism-pp.md)
[ "$(printf '%s\n' "$SCP" | grep -c FILL)" = "0" ] && ok "scaffold --preset leaves no FILL placeholder" || bad "preset has FILL"
[ "$(printf '%s\n' "$SCP" | grep -c '^Type:')" = "6" ] && ok "scaffold --preset emits 6 records (N=1)" || bad "preset record count"
printf '%s\n' "$SCP" | grep -q '^Lens: Adversarial' && ok "preset 'review' puts a heavy lens on slot 1" || bad "preset slot-1 lens"
expect_err "scaffold rejects an unknown --preset" "$LAUNCH" scaffold --preset nope
expect_err "scaffold rejects --preset with --n > 1" "$LAUNCH" scaffold --n 2 --preset review
# a preset scaffold round-trips through prepare (lenses are valid, not FILL)
printf '## Full Question\nq\n\n## Context\nc\n' > /tmp/prism-pp.md
"$LAUNCH" scaffold --preset review --packet /tmp/prism-pp.md > /tmp/prism-pp.dispatch
expect_ok "a preset scaffold round-trips through prepare" "$LAUNCH" prepare --dispatch /tmp/prism-pp.dispatch
# prepare prints the expected-notification count (capture first — grep -q on the pipe would SIGPIPE prepare mid-dump)
"$LAUNCH" prepare --dispatch /tmp/prism-pp.dispatch >"$TMP/ppnotif.out" 2>/dev/null
grep -q 'wait for 2 completion notification' "$TMP/ppnotif.out" && ok "prepare prints the expected-notification count" || bad "notification-count line"

echo "== parallax --only: single-peer retry targeting (dry-run) =="
MPP=/tmp/prism-pp-manifest.json
"$LAUNCH" parallax "$MPP" --only codex --dry-run 2>/dev/null | grep -q 'relay call --to codex --name prism-correctness' && ok "--only matches a peer by model" || bad "--only by model"
"$LAUNCH" parallax "$MPP" --only outsider --dry-run 2>/dev/null | grep -q 'relay call --to mimo --name prism-outsider' && ok "--only matches a peer by lens slug" || bad "--only by slug"
"$LAUNCH" parallax "$MPP" --only prism-correctness --dry-run 2>/dev/null | grep -q 'relay call --to codex' && ok "--only matches a peer by relay name" || bad "--only by name"
expect_err "--only refuses an unknown peer" "$LAUNCH" parallax "$MPP" --only nope --dry-run

echo "== parallax --only: real (fake-relay) retry + merge, fail-closed =="
# Build a fake skill tree so prism-launch resolves a STUB relay sibling (no network,
# no recursion). This exercises the real merge path the dry-run tests can't reach.
FT="$TMP/ft"; mkdir -p "$FT/prism/scripts" "$FT/relay/scripts"
cp "$LAUNCH" "$FT/prism/scripts/prism-launch"
ln -s "$HERE/../templates"        "$FT/prism/templates"
ln -s "$HERE/../../relay/peers.json" "$FT/relay/peers.json"
cat > "$FT/relay/scripts/relay" <<'FAKE'
#!/usr/bin/env bash
name=""; while [ $# -gt 0 ]; do case "$1" in --name) name="${2:-}"; shift 2 ;; *) shift ;; esac; done
res="$(cd "$(dirname "$0")/.." && pwd)/FAKE-$name.res.md"; echo "fake response body" > "$res"
echo "relay: response → $res" >&2
FAKE
chmod +x "$FT/relay/scripts/relay"
FL="$FT/prism/scripts/prism-launch"
FPK="$TMP/prism-fakeonly.md"; printf '## Full Question\nq\n\n## Context\nc\n' > "$FPK"
printf 'Shared-Packet: %s\n\nType: parallax\nTo: codex\nEffort: m\nLens: Alpha\nLens-Desc: weigh a\n\nType: parallax\nTo: deepseek\nLens: Beta\nLens-Desc: weigh b\n' "$FPK" > "$TMP/fakeonly.dispatch"
"$FL" prepare --dispatch "$TMP/fakeonly.dispatch" >/dev/null 2>&1
FMAN="$TMP/prism-fakeonly-manifest.json"; FRES="$TMP/prism-fakeonly-result.json"
"$FL" parallax "$FMAN" >/dev/null 2>&1
{ [ "$(jq '.results|length' "$FRES" 2>/dev/null)" = "2" ] && [ "$(jq '.succeeded' "$FRES" 2>/dev/null)" = "2" ]; } && ok "fake fan wrote a 2-peer result" || bad "fake fan result"
"$FL" parallax "$FMAN" --only codex >/dev/null 2>&1
{ [ "$(jq '.results|length' "$FRES")" = "2" ] && [ "$(jq '[.results[]|select(.name=="prism-alpha")]|length' "$FRES")" = "1" ]; } && ok "--only retry replaces one peer (no dup; count stays 2)" || bad "--only merge replace"
# fail-closed: an EMPTY existing result must not be silently kept empty
: > "$FRES"; "$FL" parallax "$FMAN" --only codex >/dev/null 2>&1
{ [ -s "$FRES" ] && jq -e '(.results|type)=="array"' "$FRES" >/dev/null 2>&1; } && ok "--only fails closed on an empty result.json" || bad "--only empty-result corruption"
# fail-closed: a MALFORMED existing result must not silently corrupt
printf 'not json{' > "$FRES"; "$FL" parallax "$FMAN" --only codex >/dev/null 2>&1
{ [ -s "$FRES" ] && jq -e '(.results|type)=="array"' "$FRES" >/dev/null 2>&1; } && ok "--only fails closed on a malformed result.json" || bad "--only malformed-result corruption"

echo "== results: structured view from result.json =="
# empty/malformed result.json is rejected, not printed as a blank summary
: > /tmp/prism-empty-result.json
printf '{"id":"prism-empty","shared_packet":"/tmp/prism-empty.md"}' > /tmp/prism-empty-manifest.json
expect_err "results rejects an empty result.json" "$LAUNCH" results /tmp/prism-empty-manifest.json
rm -f /tmp/prism-empty*
printf '{"id":"prism-pp","expected":2,"succeeded":2,"failed":0,"results":[{"to":"codex","name":"prism-correctness","status":"done","res":"/tmp/a.res.md","log":"/tmp/a.log"},{"to":"mimo","name":"prism-outsider","status":"done","res":"/tmp/b.res.md","log":"/tmp/b.log"}]}' > /tmp/prism-pp-result.json
RES=$("$LAUNCH" results "$MPP")
printf '%s\n' "$RES" | grep -q '/tmp/a.res.md' && printf '%s\n' "$RES" | grep -q '2/2 succeeded' && ok "results prints each peer's .res.md path + summary" || bad "results output"
expect_ok "results exits 0 when all peers succeeded" "$LAUNCH" results "$MPP"
printf '{"id":"prism-pp","expected":1,"succeeded":0,"failed":1,"results":[{"to":"mimo","name":"prism-outsider","status":"error","res":null,"log":"/tmp/b.log"}]}' > /tmp/prism-pp-result.json
expect_err "results exits non-zero when a peer failed" "$LAUNCH" results "$MPP"
printf '{"id":"prism-nores","shared_packet":"/tmp/prism-nores.md"}' > /tmp/prism-nores-manifest.json
expect_err "results errors when no result file exists yet" "$LAUNCH" results /tmp/prism-nores-manifest.json
"$LAUNCH" clean pp >/dev/null; rm -f /tmp/prism-nores*

echo "== digest: extract ## Digest blocks (lineage-tagged, compaction-only) =="
DGP="$TMP/prism-dg.md"            # packet path only used to derive sibling artifact paths
DGMAN="$TMP/prism-dg-manifest.json"; DGRES="$TMP/prism-dg-result.json"; DGOUT="$TMP/prism-dg-digest.md"
RA="$TMP/dg-a.res.md"; RB="$TMP/dg-b.res.md"
cat > "$RA" <<'RES'
---
from: codex
---
Long analysis body here.
More reasoning.

## Digest
- Position: pick option B
- Key reasons: removes shared state
- Dissent/caveat: none
- Changes if: p99 > 50ms
RES
printf -- '---\nfrom: grok-composer\n---\nBody with no digest section at all.\n' > "$RB"
printf '{"id":"prism-dg","shared_packet":"%s"}' "$DGP" > "$DGMAN"
printf '{"id":"prism-dg","expected":3,"succeeded":2,"failed":1,"results":[{"to":"codex","name":"prism-alpha","status":"done","res":"%s","log":"/tmp/a.log"},{"to":"grok-composer","name":"prism-beta","status":"done","res":"%s","log":"/tmp/b.log"},{"to":"mimo","name":"prism-gamma","status":"error","res":null,"log":"/tmp/c.log"}]}' "$RA" "$RB" > "$DGRES"
expect_ok "digest succeeds on a finished run" "$LAUNCH" digest "$DGMAN"
[ -f "$DGOUT" ] && ok "digest writes <id>-digest.md by default" || bad "digest output file"
grep -q 'Position: pick option B' "$DGOUT" && ok "digest extracts the ## Digest block body" || bad "digest extracts block"
! grep -q 'Long analysis body here' "$DGOUT" && ok "digest omits the full answer body (compaction)" || bad "digest leaked full body"
grep -q 'lineage: grok' "$DGOUT"  && ok "digest collapses grok-composer to the grok lineage" || bad "digest grok lineage"
grep -q 'lineage: codex' "$DGOUT" && ok "digest tags the codex lineage" || bad "digest codex lineage"
grep -q 'block found'  "$DGOUT" && ok "digest flags a peer with no ## Digest block" || bad "digest missing-block note"
grep -q 'peer failed'  "$DGOUT" && ok "digest flags a failed peer" || bad "digest failed-peer note"
grep -qF "$RA" "$DGOUT" && ok "digest cites the full .res.md path for deep-reads" || bad "digest cites res path"
"$LAUNCH" digest "$DGMAN" --out "$TMP/dg-custom.md" >/dev/null 2>&1
[ -f "$TMP/dg-custom.md" ] && ok "digest honors --out" || bad "digest --out"
printf '{"id":"prism-dgx","shared_packet":"%s"}' "$TMP/prism-dgx.md" > "$TMP/prism-dgx-manifest.json"
expect_err "digest errors when no result file exists yet" "$LAUNCH" digest "$TMP/prism-dgx-manifest.json"
: > "$TMP/prism-dgm-result.json"; printf '{"id":"prism-dgm","shared_packet":"%s"}' "$TMP/prism-dgm.md" > "$TMP/prism-dgm-manifest.json"
expect_err "digest rejects an empty result.json" "$LAUNCH" digest "$TMP/prism-dgm-manifest.json"

echo "== digest: hardened extraction edge cases (fence/colon/nested/multiple/%) =="
DHP="$TMP/prism-dh.md"; DHMAN="$TMP/prism-dh-manifest.json"; DHRES="$TMP/prism-dh-result.json"; DHOUT="$TMP/prism-dh-digest.md"
# fenced whole digest + trailing prose: must NOT leak the trailing prose (degrades to a miss)
RC="$TMP/dh-fenced.res.md"; cat > "$RC" <<'RES'
Intro body.

```
## Digest
- Position: fenced position only
```

LEAKED-TRAILING-PROSE-MUST-NOT-APPEAR
RES
# `## Digest:` with a trailing colon must still extract
RD="$TMP/dh-colon.res.md"; printf '## Digest:\n- Position: colon-variant-captured\n- Changes if: none\n' > "$RD"
# a deeper `###` inside the digest must NOT truncate it
RN="$TMP/dh-nested.res.md"; printf '## Digest\n- Position: nested-test\n### sub-note\n- Changes if: still-here-after-subheading\n' > "$RN"
# two `## Digest` headings: the LAST one wins (template says "end your answer with")
RM="$TMP/dh-multi.res.md"; printf 'Draft:\n## Digest\n- Position: FIRST-draft-should-lose\nRevised. Final:\n## Digest\n- Position: SECOND-final-should-win\n' > "$RM"
# `%` and backtick in the body survive (printf '%s' regression guard)
RP="$TMP/dh-percent.res.md"; printf '## Digest\n- Position: 100%% coverage with `jq` parsing\n- Changes if: none\n' > "$RP"
printf '{"id":"prism-dh","shared_packet":"%s"}' "$DHP" > "$DHMAN"
jq -n --arg rc "$RC" --arg rd "$RD" --arg rn "$RN" --arg rm "$RM" --arg rp "$RP" \
  '{id:"prism-dh",expected:5,succeeded:5,failed:0,results:[
    {to:"codex",name:"prism-fenced",status:"done",res:$rc,log:"/tmp/x.log"},
    {to:"deepseek",name:"prism-colon",status:"done",res:$rd,log:"/tmp/x.log"},
    {to:"mimo",name:"prism-nested",status:"done",res:$rn,log:"/tmp/x.log"},
    {to:"grok-composer",name:"prism-multi",status:"done",res:$rm,log:"/tmp/x.log"},
    {to:"grok-build",name:"prism-percent",status:"done",res:$rp,log:"/tmp/x.log"}
  ]}' > "$DHRES"
"$LAUNCH" digest "$DHMAN" >/dev/null 2>&1
! grep -q 'LEAKED-TRAILING-PROSE' "$DHOUT" && ok "fenced digest does not leak trailing prose (degrades to a miss)" || bad "fenced digest leaked trailing prose"
grep -q 'colon-variant-captured'        "$DHOUT" && ok "extracts a '## Digest:' colon-variant heading" || bad "colon-variant missed"
grep -q 'still-here-after-subheading'   "$DHOUT" && ok "a nested ### does not truncate the digest" || bad "nested ### truncated the digest"
grep -q 'SECOND-final-should-win'       "$DHOUT" && ! grep -q 'FIRST-draft-should-lose' "$DHOUT" && ok "multiple ## Digest: the last one wins" || bad "multiple-digest last-wins"
grep -q '100% coverage with `jq`'       "$DHOUT" && ok "percent + backtick in body survive (printf '%s' safe)" || bad "percent/backtick body mangled"

echo "== prepare: clears a stale -digest.md on re-run =="
make_packet "$TMP/prism-stale.md"
printf 'Shared-Packet: %s\n\nType: subagent\nLens: Xstale\nLens-Desc: y\n' "$TMP/prism-stale.md" > "$TMP/stale.dispatch"
"$LAUNCH" prepare --dispatch "$TMP/stale.dispatch" >/dev/null 2>&1
touch "$TMP/prism-stale-digest.md"
"$LAUNCH" prepare --dispatch "$TMP/stale.dispatch" >/dev/null 2>&1
[ ! -e "$TMP/prism-stale-digest.md" ] && ok "re-prepare clears a stale -digest.md" || bad "stale -digest.md not cleared on re-prepare"

echo "== subcommand --help =="
"$LAUNCH" scaffold --help 2>/dev/null | grep -q 'Usage:' && ok "scaffold --help prints usage" || bad "scaffold --help"

echo
echo "==== $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]
