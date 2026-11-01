# PrecisionTube

An iPhone and iPad YouTube player for learning crochet and knitting from videos, plus a
patterns and tools section.

## What it does

**Player**
- Step one frame at a time (hold the button to keep stepping), or 2, 5 or 10 frames per step.
- A zoomable timeline: pinch it, or use Frames / 3s / 15s / 1m / All, until there's one tick per
  frame, then drag the timeline itself to scrub. The bar under it shows the whole video.
- Speeds from 0.1× to 2×.
- Pinch the video to zoom into the hands (up to 8×); drag to move around, double-tap to reset,
  tap to play/pause.
- Repeat a section (set A and B), and bookmarks ("marks") for the start of a stitch or row.
- Remembers where you stopped in every video. The frame rate is measured while the video plays;
  you can set it by hand from the ⋯ menu.
- iPad keyboard: space play/pause, ← → one frame, shift ← → one second, ↑ ↓ zoom the timeline.

**Videos**: paste a link copied from the YouTube app (Share → Copy Link), or search in the
YouTube tab and tap *Open in frame-by-frame player*. Recent videos and favorites are listed.

**Patterns**: starter crochet and knitting patterns, your own patterns (paste one in; each line
becomes a row to tick off, with a row counter), a searchable stitch dictionary with US/UK names
and a *Find a video of this* button, and short guides.

**Tools**: row/stitch counters, increase/decrease evenly calculator, gauge calculator, hook and
needle sizes, yarn weights, US ↔ UK terms.

## How precise is it?

The player is YouTube's own embed. The page is loaded so that the app can reach the embed's
video element directly ("Precise mode", shown under the controls): seeks land on exact frames,
and slow speeds below 0.25× work. If YouTube ever stops allowing that, the app falls back to the
official player API ("Basic mode"), where frame steps are still 1/fps seeks but the slowest speed
is 0.25×. Some videos can't be played outside YouTube at all (the owner disables embedding); the
player says so and offers to open them in YouTube.

## Building and TestFlight

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen && xcodegen generate`). iOS 17 or later.

CI is the shared workflow from Dev_deploy_setup (`.github/workflows/ios-testflight.yml`), and the
App Store Connect secrets were copied in by its *Set up app repo* action:

- push to `main` with `*b` in the commit subject: archive only (a build check);
- `*u`: archive and upload to TestFlight (build number + 1);
- tag `v1.1.0` on a `*u` commit to start a new version;
- Actions → iOS TestFlight → Run workflow: always uploads.

Bundle ID `com.coralcoder.precisiontube`; App Store Connect name `PrecisionTubeCrafts` (the
scheme name); the home-screen name is *PrecisionTube*.
