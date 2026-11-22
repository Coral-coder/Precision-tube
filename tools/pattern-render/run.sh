#!/bin/bash
# Build the renderer from the app's own sources and draw a pattern.
# Usage: tools/pattern-render/run.sh patterns/baby-grogu.txt out.png
set -e
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../PrecisionTube"
out="${TMPDIR:-/tmp}/pattern-render"
mkdir -p "$out"
swiftc -O -o "$out/pattern-render" "$src/Patterns/PatternText.swift" "$src/Shapes/ShapeMath.swift" \
  "$src/Shapes/StitchMesh.swift" "$src/Shapes/Assembly.swift" "$here/main.swift"
"$out/pattern-render" "$1" "$out/mesh.json"
python3 "$here/render.py" "$out/mesh.json" "$2"
