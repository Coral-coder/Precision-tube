# pattern-render

Renders a pattern with the app's own pattern and 3D code (`PatternText.swift`,
`ShapeMath.swift`, `StitchMesh.swift`, `Assembly.swift`) so the 3D preview can be checked
without a phone. It prints what it read from the pattern (pieces, stitch counts, colour
changes, collars, attachments, eyes) and draws front, three-quarter and side views.

```
tools/pattern-render/run.sh tools/pattern-render/patterns/baby-grogu.txt grogu.png
```

To see it part made, the way the editor and the pattern page show it, set `UPTO` to a line
(0-based, counting non-blank lines) when running the built binary; that line's round glows.

Render every test pattern (and print what was read from each) with:

```
tools/pattern-render/render-all.sh out/
```

Test patterns (all written for these tests), each with its expected picture next to it:
`baby-grogu` (colour change, collar, eyes, closed-leaf ears sideways), `penguin-with-hat`
(three colours, wings, a hat draping over the top), `bunny` (head on body, long standing ears,
arms, legs, "make 2"), `teddy` (muzzle, cupped ears, arms, legs), `cat` ("[6]" counts, pointed
ears, tail at the back), `chick` (beak on the front, wings), `octopus` (eight legs splayed
under), `mushroom` (cap resting on a narrower stem), `whale` (paired tail fins), `strawberry`
("= 6" counts, a flat leaf cap), `snake` (a long piece lies down) and `scarf-flat` (rows,
nothing to draw). Look at every picture after a change to the shape code.

Needs a Swift toolchain (macOS, or Linux from swift.org) and Python with matplotlib and numpy.
Add a pattern to `patterns/` when the preview gets one wrong, and check the picture after
any change to the shape code.
