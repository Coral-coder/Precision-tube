# Taking StitchStep public

Everything needed to go from TestFlight to the App Store, in order. Copy-paste text for the
store fields is in [app-store-listing.md](app-store-listing.md), the note for Apple's reviewers
in [review-notes.md](review-notes.md), and the privacy policy and support page in
[../privacy.md](../privacy.md) and [../support.md](../support.md).

## 1. Fix this first: the YouTube player as it is now will not pass

The TestFlight build is fine for you and your partner. A public build has to follow
YouTube's API rules and Apple's review rules, and the current player breaks both in ways a
reviewer (or YouTube) can see:

| What the app does now | Rule it runs into |
| --- | --- |
| Hides YouTube's own controls, title bar, logo and "More videos" | YouTube Developer Policies: don't modify, add to or block the standard player or its links |
| Injects a script into YouTube's player and drives its `<video>` element (exact frames, 0.1× speed) | Same; also only the IFrame API is a supported way to control playback |
| Puts our controls over the video in landscape, and zooms the player | Required Minimum Functionality: no overlays on the player, size rules |
| A YouTube tab that is the full mobile YouTube site in a web view | Apple 5.2.2/5.2.3 (third-party content); also counts as unrestricted web access, which raises the age rating |
| Core value is watching other people's YouTube videos | Apple often rejects these under 5.2.3 and asks for proof of rights |

**What a store-safe version looks like** (I can build it; it's a few days of work):

1. **"Store mode" YouTube player**: YouTube's embed left exactly as YouTube draws it, controlled
   only through the IFrame API. Frame stepping still works (it seeks 1/30 s at a time), speed
   0.25×–2×, A/B repeat, marks, playlists and resume all stay. Our controls sit *below or
   beside* the player, never on top of it, and there's no video zoom on YouTube videos.
2. **Your own videos, with full precision**: import a video from Photos or Files (a screen
   recording, a class video you bought, one you filmed). These play in Apple's own player,
   so exact frame stepping, 0.1× slow motion and pinch-zoom are all allowed. This becomes
   the headline feature and the thing worth paying for.
3. **Replace the YouTube tab** with a Share Extension: in the YouTube app, Share →
   StitchStep. No web browser inside the app, so the age rating can stay low.
4. Keep everything that isn't YouTube: patterns, row counters, tools, Shape Studio (marked
   experimental), app color.

Apple may still ask about YouTube under 5.2.3. The answer is in
[review-notes.md](review-notes.md): playback is YouTube's official embedded player, nothing is
downloaded, and the paid features don't depend on YouTube.

## 2. Pricing

**Recommendation: free download, plus a one-time "StitchStep Pro" unlock at $6.99
($4.99 launch price for the first two weeks).**

- **Free**: YouTube and own-video playback with frame stepping, speed, A/B repeat and marks,
  2 row counters, the starter patterns, the stitch dictionary and the guides.
- **Pro ($6.99, once)**: full-precision tools on your own videos (0.1× and pinch-zoom),
  unlimited saved patterns with row check-off, unlimited counters, landscape edge buttons,
  Shape Studio and 3D preview, the calculators.

Why this shape:

- **Don't charge for watching YouTube.** Keeping YouTube playback free keeps the paywall on
  our own features. That's the safest reading of YouTube's rules and easier to explain to
  App Review.
- **One-time, not a subscription.** Crafters put up with paying once for a tool; a monthly
  fee for a counter and a player feels wrong, and subscriptions get extra review scrutiny.
- **Free with an unlock gets far more downloads** than a paid-up-front app. People try it on
  one tricky stitch, then pay.
- **$6.99** is impulse-sized for a hobby tool with no ongoing costs (no servers). After
  Apple's 15% (Small Business Program) that's about $5.94 a sale before tax.

This is a judgment call. I haven't surveyed competitors' prices. Charging $2.99 or $9.99
would also be reasonable. The in-app purchase needs code (StoreKit 2, about a day), and I can
build it with the store-safe version.

## 3. Things only you can do (Apple account, about an hour, phone OK)

In App Store Connect (appstoreconnect.apple.com):

1. **Business → Agreements**: accept the **Paid Apps** agreement. Needed for in-app purchases.
2. **Business → Banking and Tax**: add a bank account and fill in the tax forms (W-9 in the
   US). Payments can't start without these.
3. **Apple Small Business Program**: enroll at developer.apple.com/app-store/small-business-program
   (15% commission instead of 30% for under $1M a year).
4. **EU Digital Services Act trader status** (App Information → App Store Regulations): to
   sell in the EU you declare yourself a trader, and your address, phone and email are then
   shown on the EU store page. Or leave the EU out under Pricing and Availability.
5. **Trademark check**: "StitchStep" was already taken on the App Store (that's why the store
   name became "StitchStep: Frame by Frame"). Search the name at tmsearch.uspto.gov before
   spending on branding.
6. **Two public web pages**: a privacy policy URL and a support URL (Apple requires both).
   The text is ready in `docs/privacy.md` and `docs/support.md`. Host them anywhere public:
   GitHub Pages on a public repo, Notion, Carrd, Google Sites. They must load without a login.
7. **A support email address** to put on those pages and in the review contact info.

## 4. App Store Connect fields (I can fill most of this through the API once you say go)

| Field | Value |
| --- | --- |
| Name | StitchStep: Frame by Frame |
| Subtitle | see listing file |
| Primary category | Lifestyle |
| Secondary category | Education |
| Content rights | "Yes, it contains third-party content" → you must have the rights; see section 1 |
| Age rating | 4+ once the in-app YouTube browser is gone (answer "None" to everything); with the browser it must declare unrestricted web access |
| App Privacy | Data Not Collected (see privacy.md) |
| Price | Free, with the Pro in-app purchase |
| Encryption | Already declared in the app (no non-exempt encryption) |
| Screenshots | 6.9" iPhone (1320 × 2868) and 13" iPad (2064 × 2752), 3–10 each |
| Review contact | your name, phone, email |
| Review notes | review-notes.md |
| Copyright | 2026 your name |

**Screenshots**: I can make CI capture them automatically on the iPhone and iPad simulators
with sample data (Player, landscape, Patterns, row counter, Shape Studio). Use your own
videos for these, not YouTube videos: other people's video frames in store screenshots are a
rights problem.

## 5. Order of work

1. I build the store-safe version: store-mode player, own-video import, Share Extension, Pro
   unlock, automatic screenshots. It goes to TestFlight for you and your partner to try.
2. You do section 3 (agreements, bank, tax, small business, the two web pages).
3. I fill the store listing, add the in-app purchase product, and attach the build.
4. You press **Submit for Review** (1–3 days). If Apple rejects it, send me the message and
   I'll fix it or draft the reply.
