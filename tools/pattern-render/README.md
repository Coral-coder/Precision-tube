# pattern-render

Renders a pattern with the app's own pattern and 3D code (`PatternText.swift`,
`ShapeMath.swift`, `StitchMesh.swift`, `Assembly.swift`) so the 3D preview can be checked
without a phone. It prints what it read from the pattern (pieces, stitch counts, colour
changes, collars, attachments, eyes) and draws front, three-quarter and side views.

```
tools/pattern-render/run.sh tools/pattern-render/patterns/baby-grogu.txt grogu.png
```

Needs a Swift toolchain (macOS, or Linux from swift.org) and Python with matplotlib and numpy.
Add a pattern to `patterns/` when the preview gets one wrong, and check the picture after
any change to the shape code.
