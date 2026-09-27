#!/usr/bin/env bash
# parity/check.sh — Phase-2 acceptance gate: byte-identical traces between the
# frozen JS engine and the GDScript port, over 50 autoplayer-driven full games.
set -euo pipefail

cd "$(dirname "$0")/.."   # godot project dir
GODOT="${GODOT:-$HOME/.local/bin/godot}"

echo "== generating JS reference traces (frozen engine) =="
node parity/trace_js.mjs parity/reference_traces.json

echo "== generating Godot port traces =="
"$GODOT" --headless --path . -s res://parity/trace_godot.gd

echo "== diffing =="
if python3 - <<'EOF'
import json, sys
a = json.load(open("parity/reference_traces.json"))
b = json.load(open("parity/traces_godot.json"))
# compare field-by-field with a precise report; exit 1 on any difference
def walk(x, y, path="$"):
    if type(x) is not type(y):
        print(f"TYPE MISMATCH at {path}: js={type(x).__name__} godot={type(y).__name__}")
        return False
    ok = True
    if isinstance(x, dict):
        for k in sorted(set(list(x.keys()) + list(y.keys()))):
            if k not in y:
                print(f"MISSING KEY at {path}.{k} (js={x[k]!r})"); ok = False; continue
            if k not in x:
                print(f"EXTRA KEY at {path}.{k} (godot={y[k]!r})"); ok = False; continue
            ok &= walk(x[k], y[k], f"{path}.{k}")
    elif isinstance(x, list):
        if len(x) != len(y):
            print(f"LENGTH MISMATCH at {path}: js={len(x)} godot={len(y)}")
            return False
        for i, (xi, yi) in enumerate(zip(x, y)):
            ok &= walk(xi, yi, f"{path}[{i}]")
    else:
        if x != y:
            print(f"VALUE MISMATCH at {path}: js={x!r} godot={y!r}")
            return False
    return ok

if a.get("protocol") != b.get("protocol"):
    print(f"PROTOCOL MISMATCH: js={a.get('protocol')!r} godot={b.get('protocol')!r}")
    sys.exit(1)
ok = walk(a, b)
print("PARITY OK — traces identical across all seeds" if ok else "PARITY FAILED")
sys.exit(0 if ok else 1)
EOF
then
  echo "== GATE PASSED: JS and Godot ports are behaviorally identical =="
else
  echo "== GATE FAILED: see mismatches above ==" >&2
  exit 1
fi
