#!/bin/bash
# Render every pattern in patterns/ to <out dir>/<name>.png and print what was read.
# Usage: tools/pattern-render/render-all.sh <out dir>
set -e
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../PrecisionTube"
out="${1:-${TMPDIR:-/tmp}/pattern-render}"
mkdir -p "$out"
swiftc -O -o "$out/pattern-render" "$src/Patterns/PatternText.swift" "$src/Shapes/ShapeMath.swift" \
  "$src/Shapes/StitchMesh.swift" "$src/Shapes/Assembly.swift" "$here/main.swift"
for f in "$here"/patterns/*.txt; do
  name="$(basename "$f" .txt)"
  echo "=== $name"
  "$out/pattern-render" "$f" "$out/$name.json" | grep -v "^  heights\|^  lines"
  python3 "$here/render.py" "$out/$name.json" "$out/$name.png" > /dev/null
done
