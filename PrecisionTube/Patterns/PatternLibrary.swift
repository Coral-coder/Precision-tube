import Foundation

struct PatternSection: Hashable {
    var title: String
    var rows: [String]
}

/// A pattern ready to follow row by row: a built-in one or one you wrote.
struct PatternContent: Identifiable, Hashable {
    var id: String
    var title: String
    var craft: Craft
    var level: String?
    var summary: String?
    var materials: [String] = []
    var notes: String?
    var sections: [PatternSection]
    var videoID: String?
    var videoSearch: String?
    var userPatternID: UUID?

    var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }
}

extension UserPattern {
    var content: PatternContent {
        PatternContent(id: "user-\(id.uuidString)", title: title, craft: craft, notes: notes.isEmpty ? nil : notes,
                       sections: [PatternSection(title: "Rows", rows: rows)], videoID: videoID, userPatternID: id)
    }
}

enum PatternLibrary {
    static let all: [PatternContent] = [
        PatternContent(
            id: "granny-square", title: "Classic Granny Square", craft: .crochet, level: "Beginner",
            summary: "The building block of blankets, bags and cardigans. Worked in the round from the center out.",
            materials: ["Worsted (weight 4) yarn, one or more colors", "5 mm (H-8) hook", "Yarn needle"],
            notes: "US terms. Beginning ch 3 counts as a dc. A cluster is 3 dc worked into the same space. Each round adds one cluster to every side.",
            sections: [
                PatternSection(title: "Center", rows: [
                    "Ch 4 and sl st into the first ch to make a ring (or use a magic ring).",
                    "Rnd 1: Ch 3, 2 dc in the ring, ch 2. *3 dc in the ring, ch 2* 3 times. Sl st to the top of the beginning ch 3. (4 clusters)",
                ]),
                PatternSection(title: "Growing the square", rows: [
                    "Rnd 2: Sl st across to the next ch-2 corner space. Ch 3, (2 dc, ch 2, 3 dc) in the same space. *Ch 1, (3 dc, ch 2, 3 dc) in the next corner space* 3 times. Ch 1, sl st to the top of the ch 3. (8 clusters)",
                    "Rnd 3: Sl st across to the corner space. Ch 3, (2 dc, ch 2, 3 dc) in the same space. *Ch 1, 3 dc in the next ch-1 space, ch 1, (3 dc, ch 2, 3 dc) in the next corner* 3 times. Ch 1, 3 dc in the last ch-1 space, ch 1, sl st to the top of the ch 3. (12 clusters)",
                    "Rnd 4: Same idea: (3 dc, ch 2, 3 dc) in every corner, 3 dc in every ch-1 space along the sides, ch 1 between clusters. (16 clusters)",
                    "Rnd 5: Repeat Rnd 4. (20 clusters)",
                    "Rnd 6: Repeat Rnd 4. (24 clusters)",
                ]),
                PatternSection(title: "Finish", rows: [
                    "Keep going until the square is the size you want (about 6 in / 15 cm after 6 rounds).",
                    "Fasten off and weave in the ends.",
                ]),
            ],
            videoSearch: "crochet granny square beginner"),

        PatternContent(
            id: "amigurumi-ball", title: "Amigurumi Ball", craft: .crochet, level: "Beginner",
            summary: "The sphere that most amigurumi (heads, bodies, balls) start from. Worked in continuous spiral rounds.",
            materials: ["Worsted (weight 4) cotton or acrylic", "3.5–4 mm hook (smaller than the label says, so stuffing doesn't show)", "Stitch marker", "Fiberfill stuffing", "Yarn needle"],
            notes: "US terms. Don't join rounds: move the stitch marker up to the first stitch of each round. inc = 2 sc in one stitch; dec = sc2tog (an invisible decrease looks neatest). The number in brackets is the stitch count at the end of the round.",
            sections: [
                PatternSection(title: "Increase", rows: [
                    "R1: 6 sc in a magic ring. (6)",
                    "R2: Inc in every stitch. (12)",
                    "R3: *Sc 1, inc* 6 times. (18)",
                    "R4: *Sc 2, inc* 6 times. (24)",
                    "R5: *Sc 3, inc* 6 times. (30)",
                ]),
                PatternSection(title: "Straight", rows: [
                    "R6: Sc in every stitch. (30)",
                    "R7: Sc in every stitch. (30)",
                    "R8: Sc in every stitch. (30)",
                    "R9: Sc in every stitch. (30)",
                    "R10: Sc in every stitch. (30)",
                ]),
                PatternSection(title: "Decrease and close", rows: [
                    "R11: *Sc 3, dec* 6 times. (24)",
                    "R12: *Sc 2, dec* 6 times. (18)",
                    "Stuff the ball firmly.",
                    "R13: *Sc 1, dec* 6 times. (12)",
                    "Top up the stuffing.",
                    "R14: Dec 6 times. (6)",
                    "Fasten off, leaving a tail. Weave the tail through the front loops of the last 6 stitches, pull tight, and hide the end inside.",
                ]),
            ],
            videoSearch: "amigurumi ball magic ring invisible decrease"),

        PatternContent(
            id: "hdc-dishcloth", title: "Half Double Crochet Dishcloth", craft: .crochet, level: "Beginner",
            summary: "Rows of hdc with a single crochet border. Great for practising even tension and turning chains.",
            materials: ["Worsted (weight 4) cotton, about 60 yd / 55 m", "5 mm (H-8) hook", "Yarn needle"],
            notes: "US terms. The turning ch 2 does not count as a stitch, so always work into the first stitch. Count 29 stitches at the end of every row.",
            sections: [
                PatternSection(title: "Body", rows: [
                    "Ch 31.",
                    "Row 1: Hdc in the 3rd ch from the hook and in every ch across. (29)",
                    "Row 2: Ch 2, turn. Hdc in every stitch across. (29)",
                    "Repeat Row 2 until the piece is square, about 20–22 rows in total.",
                ]),
                PatternSection(title: "Border", rows: [
                    "Ch 1, don't turn. Sc evenly down the side, about 1 sc per row end.",
                    "Work 3 sc in each corner and 1 sc in each stitch or chain along the top and bottom.",
                    "Sl st to the first sc. Fasten off and weave in the ends.",
                ]),
            ],
            videoSearch: "half double crochet dishcloth beginner"),

        PatternContent(
            id: "ribbed-beanie", title: "Ribbed Beanie (worked flat)", craft: .crochet, level: "Beginner",
            summary: "A stretchy hat made as one rectangle of back-loop half double crochet, seamed and cinched at the top.",
            materials: ["Worsted (weight 4) yarn, about 180 yd / 165 m", "5.5 mm (I-9) hook", "Yarn needle"],
            notes: "US terms. Working in the back loop only (BLO) makes the ribs. The row count sets the hat's width around your head; the chain sets its height. Measure the head and stop the rectangle about 2 in / 5 cm short of that (it stretches).",
            sections: [
                PatternSection(title: "Rectangle", rows: [
                    "Ch 40 (about 9 in / 23 cm for an adult hat with a fold-up brim; add or remove chains to change the height).",
                    "Row 1: Hdc in the 3rd ch from the hook and in every ch across. (38)",
                    "Row 2: Ch 2, turn. Hdc BLO in every stitch across. (38)",
                    "Repeat Row 2 until the rectangle measures about 18–19 in / 46–48 cm along the row edges (adult) when laid flat without stretching.",
                ]),
                PatternSection(title: "Make it a hat", rows: [
                    "Fold the rectangle in half, matching the first and last rows. Sl st (or whip stitch) them together to make a tube.",
                    "Weave a long piece of yarn in and out through the row ends along one open edge.",
                    "Pull it tight to close the top, knot securely, and weave in the ends.",
                    "Turn right side out and fold up the brim. Add a pom-pom if you like.",
                ]),
            ],
            videoSearch: "crochet ribbed beanie flat hdc blo"),

        PatternContent(
            id: "garter-dishcloth", title: "Diagonal Garter Dishcloth", craft: .knitting, level: "Beginner",
            summary: "The classic corner-to-corner cloth: knit every row, increase to the middle, decrease back down.",
            materials: ["Worsted (weight 4) cotton, about 70 yd / 64 m", "US 7 (4.5 mm) straight needles", "Yarn needle"],
            notes: "Every row is knitted. The yarn over (yo) at the start of each row makes the pretty eyelet edge.",
            sections: [
                PatternSection(title: "Increase half", rows: [
                    "Cast on 4 stitches.",
                    "Row 1: Knit across. (4)",
                    "Row 2: K2, yo, knit to the end. (5)",
                    "Repeat Row 2 until you have 44 stitches (or the cloth is as wide as you want across the diagonal).",
                ]),
                PatternSection(title: "Decrease half", rows: [
                    "Decrease row: K1, k2tog, yo, k2tog, knit to the end. (1 fewer stitch)",
                    "Repeat the decrease row until 4 stitches remain.",
                    "Bind off and weave in the ends.",
                ]),
            ],
            videoSearch: "knit diagonal dishcloth grandmother's favorite"),

        PatternContent(
            id: "rib-scarf", title: "2×2 Ribbed Scarf", craft: .knitting, level: "Beginner",
            summary: "Reversible, squishy, and lies flat. Practises switching between knit and purl.",
            materials: ["Worsted (weight 4) yarn, about 300 yd / 275 m", "US 8 (5 mm) needles", "Yarn needle"],
            notes: "The stitch count is a multiple of 4 plus 2. Move the yarn between the needles when you switch from knit to purl (to the front to purl, to the back to knit).",
            sections: [
                PatternSection(title: "Scarf", rows: [
                    "Cast on 34 stitches (or any multiple of 4, plus 2).",
                    "Row 1 (right side): K2, *p2, k2* to the end.",
                    "Row 2 (wrong side): P2, *k2, p2* to the end.",
                    "Repeat Rows 1 and 2 until the scarf is about 60 in / 150 cm long.",
                    "Bind off in pattern (knit the knits and purl the purls as you bind off). Weave in the ends.",
                ]),
            ],
            videoSearch: "knit 2x2 rib scarf beginner"),
    ]
}

struct Stitch: Identifiable, Hashable {
    var id: String { craft.rawValue + abbr }
    var abbr: String
    var name: String
    var craft: Craft
    var uk: String?
    var how: String
}

enum StitchGlossary {
    static let all: [Stitch] = [
        // Crochet, US terms
        Stitch(abbr: "ch", name: "Chain", craft: .crochet, how: "Yarn over and pull through the loop on the hook. Count chains by the V's, never counting the loop on the hook."),
        Stitch(abbr: "sl st", name: "Slip stitch", craft: .crochet, uk: "ss", how: "Insert the hook, yarn over, and pull through both the stitch and the loop on the hook in one go. Used for joining rounds and moving along without adding height."),
        Stitch(abbr: "sc", name: "Single crochet", craft: .crochet, uk: "dc (double crochet)", how: "Insert the hook, yarn over, pull up a loop (2 loops on hook), yarn over and pull through both loops."),
        Stitch(abbr: "hdc", name: "Half double crochet", craft: .crochet, uk: "htr (half treble)", how: "Yarn over, insert the hook, yarn over and pull up a loop (3 loops), yarn over and pull through all 3."),
        Stitch(abbr: "dc", name: "Double crochet", craft: .crochet, uk: "tr (treble)", how: "Yarn over, insert the hook, pull up a loop (3 loops). Yarn over, pull through 2. Yarn over, pull through the last 2."),
        Stitch(abbr: "tr", name: "Treble (triple) crochet", craft: .crochet, uk: "dtr (double treble)", how: "Yarn over twice, insert the hook, pull up a loop (4 loops). *Yarn over, pull through 2* three times."),
        Stitch(abbr: "MR", name: "Magic ring", craft: .crochet, how: "Wrap the yarn into a loop around your fingers, insert the hook, pull up a loop and chain 1 to secure. Work the first round into the ring, then pull the tail to close the hole completely."),
        Stitch(abbr: "inc", name: "Increase", craft: .crochet, how: "Work 2 stitches into the same stitch. In amigurumi it usually means 2 sc in one stitch."),
        Stitch(abbr: "dec / sc2tog", name: "Single crochet two together", craft: .crochet, uk: "dc2tog", how: "Insert into the next stitch and pull up a loop, insert into the following stitch and pull up a loop (3 loops), yarn over and pull through all 3."),
        Stitch(abbr: "invdec", name: "Invisible decrease", craft: .crochet, how: "Insert the hook into the front loop only of the next 2 stitches, yarn over and pull through both front loops (2 loops on hook), yarn over and pull through both. Neater than sc2tog for amigurumi."),
        Stitch(abbr: "FLO / BLO", name: "Front / back loop only", craft: .crochet, how: "Each stitch top is a V with a front loop (nearest you) and a back loop. Work into just that one loop. BLO rows make ribbing and leave a visible line."),
        Stitch(abbr: "FPdc", name: "Front post double crochet", craft: .crochet, uk: "FPtr", how: "Yarn over, insert the hook from front to back to front around the post (the stem) of the stitch below, then finish as a dc. The stitch pops toward you."),
        Stitch(abbr: "BPdc", name: "Back post double crochet", craft: .crochet, uk: "BPtr", how: "Yarn over, insert the hook from back to front to back around the post of the stitch below, then finish as a dc. Alternating FPdc and BPdc makes ribbing."),
        Stitch(abbr: "puff", name: "Puff stitch", craft: .crochet, how: "*Yarn over, insert, pull up a long loop* 3–5 times in the same stitch, yarn over and pull through all loops, then often ch 1 to close."),
        Stitch(abbr: "bobble", name: "Bobble", craft: .crochet, how: "Work 5 dc into the same stitch but leave the last loop of each on the hook (6 loops), then yarn over and pull through all of them."),
        Stitch(abbr: "pc", name: "Popcorn", craft: .crochet, how: "Work 5 complete dc in one stitch, take the hook out, insert it into the first dc, pick up the dropped loop and pull it through."),
        Stitch(abbr: "shell", name: "Shell", craft: .crochet, how: "Several tall stitches (often 5 dc) in the same stitch, fanning out. Usually separated by skipped stitches and sc."),
        Stitch(abbr: "V-st", name: "V-stitch", craft: .crochet, how: "(Dc, ch 1, dc) in the same stitch. On the next row work the V-stitch into the ch-1 space."),
        Stitch(abbr: "rev sc", name: "Reverse single crochet (crab stitch)", craft: .crochet, how: "Single crochet worked from left to right (for right-handers) for a twisted, corded edge."),
        Stitch(abbr: "fsc", name: "Foundation single crochet", craft: .crochet, how: "Makes the chain and first row at once: a stretchy edge with no separate chain to work into."),
        Stitch(abbr: "yo", name: "Yarn over", craft: .crochet, uk: "yrh (yarn round hook)", how: "Wrap the yarn over the hook from back to front."),
        Stitch(abbr: "sk / sp", name: "Skip / space", craft: .crochet, how: "Sk: miss the stitch. Sp: the gap made by chains in the row below (e.g. 'ch-1 sp'); work into the hole, not into the chain itself."),
        Stitch(abbr: "tch", name: "Turning chain", craft: .crochet, how: "Chains at the start of a row to reach the height of the stitches: 1 for sc, 2 for hdc, 3 for dc. The pattern says whether it counts as a stitch."),
        Stitch(abbr: "* … *", name: "Repeat markers", craft: .crochet, how: "Repeat the steps between the asterisks as many times as stated. Parentheses ( ) group steps worked in the same stitch; a number in brackets at the end is the stitch count."),

        // Knitting
        Stitch(abbr: "CO", name: "Cast on", craft: .knitting, how: "Put the first stitches on the needle. The long-tail cast on is stretchy and neat; leave a tail about 1 in / 2.5 cm per stitch."),
        Stitch(abbr: "BO", name: "Bind off", craft: .knitting, uk: "cast off", how: "Knit 2, pass the first stitch over the second. *Knit 1, pass the previous stitch over* to the end. Cut the yarn and pull it through the last loop."),
        Stitch(abbr: "k", name: "Knit", craft: .knitting, how: "With yarn in back, insert the right needle front to back through the stitch, wrap the yarn, pull the new loop through and slip the old stitch off."),
        Stitch(abbr: "p", name: "Purl", craft: .knitting, how: "With yarn in front, insert the right needle back to front (right to left) through the front of the stitch, wrap, pull through and slip the old stitch off."),
        Stitch(abbr: "k2tog", name: "Knit two together", craft: .knitting, how: "Knit the next 2 stitches together as one. A right-leaning decrease."),
        Stitch(abbr: "ssk", name: "Slip, slip, knit", craft: .knitting, how: "Slip 2 stitches knitwise one at a time, put the left needle into their fronts and knit them together. A left-leaning decrease."),
        Stitch(abbr: "p2tog", name: "Purl two together", craft: .knitting, how: "Purl the next 2 stitches together as one."),
        Stitch(abbr: "yo", name: "Yarn over", craft: .knitting, uk: "yfwd / yrn", how: "Bring the yarn over the right needle to make a new loop: an increase that leaves a decorative hole (eyelet)."),
        Stitch(abbr: "kfb", name: "Knit front and back", craft: .knitting, how: "Knit into the front of the stitch but leave it on the needle, then knit into its back loop and slip it off. Makes 2 from 1."),
        Stitch(abbr: "M1L", name: "Make 1 left", craft: .knitting, how: "Lift the bar between stitches from front to back with the left needle and knit it through the back loop. Left-leaning increase."),
        Stitch(abbr: "M1R", name: "Make 1 right", craft: .knitting, how: "Lift the bar between stitches from back to front and knit it through the front loop. Right-leaning increase."),
        Stitch(abbr: "sl", name: "Slip", craft: .knitting, how: "Move a stitch to the right needle without working it: purlwise unless the pattern says knitwise."),
        Stitch(abbr: "tbl", name: "Through the back loop", craft: .knitting, how: "Work into the back leg of the stitch, which twists it."),
        Stitch(abbr: "pm / sm", name: "Place / slip marker", craft: .knitting, how: "Put a stitch marker on the needle, or move it from the left to the right needle as you reach it."),
        Stitch(abbr: "wyif / wyib", name: "With yarn in front / back", craft: .knitting, how: "Where the working yarn should be while you slip a stitch."),
        Stitch(abbr: "st st", name: "Stockinette stitch", craft: .knitting, how: "Flat: knit right-side rows, purl wrong-side rows. In the round: knit every round. Smooth V's on the front; the edges curl."),
        Stitch(abbr: "garter", name: "Garter stitch", craft: .knitting, how: "Flat: knit every row. Bumpy ridges on both sides, lies flat."),
        Stitch(abbr: "rib", name: "Ribbing", craft: .knitting, how: "Alternate knits and purls in a column pattern (k1 p1 or k2 p2). Knit the knits and purl the purls on the following rows. Stretchy; used for cuffs and brims."),
        Stitch(abbr: "seed", name: "Seed stitch", craft: .knitting, uk: "moss stitch", how: "Alternate k1 and p1, and on the next row knit the purls and purl the knits, so the bumps checkerboard."),
        Stitch(abbr: "RS / WS", name: "Right side / wrong side", craft: .knitting, how: "The side that faces out on the finished piece, and the back of it."),
    ]
}

struct Guide: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var icon: String
    var paragraphs: [String]
}

enum GuideLibrary {
    static let all: [Guide] = [
        Guide(title: "Learning a stitch from a video", icon: "scope", paragraphs: [
            "Open the video, then find the moment the stitch starts. Tap Mark this spot so you can jump back to it.",
            "Set A at the start of one stitch and B at the end, then turn on repeat: the section plays over and over while you copy it.",
            "Drop the speed to 0.25× or 0.1× to see where the hook goes. Pause and use the frame buttons (or hold them down) to step through the exact moment the yarn is caught.",
            "Pinch the video to zoom into the hands. Drag to move around while zoomed; double-tap to go back.",
            "Pinch the timeline to zoom it in until you see one tick per frame, then drag the timeline itself for very fine scrubbing.",
            "With a keyboard on iPad: space plays and pauses, ← → step a frame, shift + ← → jump a second, ↑ ↓ zoom the timeline.",
        ]),
        Guide(title: "Reading a crochet pattern", icon: "text.book.closed", paragraphs: [
            "Check whether the pattern uses US or UK terms. A UK 'double crochet' is a US single crochet (see Stitches for the full list).",
            "Rnd means round (worked in a circle); Row means you turn the work at the end.",
            "Text between asterisks * … * is repeated as many times as it says. Steps in parentheses ( ) are all worked into the same stitch or space.",
            "The number at the end of a row, like (24), is how many stitches you should have. Count every few rows: it catches mistakes early.",
            "Use a stitch marker in the first stitch of each round, especially in spiral rounds (amigurumi) where there's no visible join.",
        ]),
        Guide(title: "Reading a knitting pattern", icon: "text.book.closed.fill", paragraphs: [
            "Patterns give stitch multiples, e.g. 'a multiple of 4 + 2': any count that is 2 more than a multiple of 4 works.",
            "RS and WS rows tell you which side faces you. In stockinette the RS is the smooth side.",
            "'Work even' means keep going in the pattern without increasing or decreasing.",
            "'Knit the knits and purl the purls' means work each stitch as it looks: a V is a knit, a bump is a purl.",
        ]),
        Guide(title: "Gauge (and why the size comes out wrong)", icon: "ruler", paragraphs: [
            "Gauge is how many stitches and rows fit in 4 in / 10 cm. If yours is different from the pattern's, the finished piece will be bigger or smaller.",
            "Make a swatch at least 5 in / 13 cm square in the pattern stitch, wash and dry it as you would the finished item, then measure in the middle.",
            "Too many stitches per 4 in: go up a hook or needle size. Too few: go down a size.",
            "The Tools tab has a gauge calculator that turns your swatch into a stitch count for any width.",
        ]),
        Guide(title: "Fixing common problems", icon: "wrench.and.screwdriver", paragraphs: [
            "Edges getting wider or narrower (crochet rows): check whether the turning chain counts as a stitch, and make sure you work into the last stitch, often hiding under the turning chain of the row below.",
            "Holes in amigurumi: use a smaller hook and the invisible decrease.",
            "Wavy, ruffled circle: too many increases, or the hook is too big. Cupping circle: too few.",
            "Dropped knit stitch: catch it with a crochet hook and ladder it back up, one bar at a time.",
            "Tight work: relax your grip on the yarn and make sure each stitch is formed on the thick part of the needle or hook shaft.",
        ]),
        Guide(title: "Yarn labels", icon: "tag", paragraphs: [
            "The label shows the weight number (0–7), fiber, length, recommended hook or needle size and gauge, and washing symbols.",
            "Buy enough from the same dye lot for the whole project: colors can differ between lots.",
            "Cotton is best for dishcloths and amigurumi (crisp stitches). Acrylic is cheap, soft and machine washable. Wool is warm and springy but can felt in a hot wash.",
        ]),
    ]
}
