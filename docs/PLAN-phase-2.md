# Phase 2 Plan — Purple: from inbox trainer to cyber exercise

> Draft for discussion. Phase 1 (`docs/PLAN.md`, M0–M10) ships first. Once this plan is agreed, work
> through its milestones **in order** (P1 → P9), one PR each, with the same conventions, tests and
> "done when" discipline as phase 1. Where this file and `docs/PLAN.md` disagree, this file wins for
> phase 2 work. Section 11 of `docs/PLAN.md` ("After the MVP") is folded in here where it fits.

## 1. Why a phase 2

Phase 1 is a solid, honest inbox trainer: the server holds every answer, nothing on screen says how
you're doing, and the Purple debrief teaches. Playtesting and a review point at four gaps:

1. **The setting is one office.** Every shift is a working day at Larkhill Finance. The stakes are
   invoices and gift cards.
2. **The attack is almost always a message.** 19 techniques, nearly all pretext, sender or lure.
   No exploitation, no cryptography, no systems, no incident response.
3. **Red is a budgeting puzzle.** Choosing one card per slot is safe and clever, but it never feels
   like breaking in.
4. **Some answers leak through the presentation, and learning isn't measured.** Sign-in pages and
   download prompts only ever appear on malicious paths. One shot per shift means a mistake uses up
   the scenario, and nothing shows a player getting better.

Phase 2 opens with something new and fun: CTF-style signals puzzles (P1). Then it fixes the fairness
and learning gaps (P2–P4), and widens the game with simulated hacking labs based on real incidents
and a tongue-in-cheek military campaign against a recurring attacker (P5–P9).

**One ladder, many kinds of challenge.** Everything sits in one progression, not separate products.
Inbox and phone shifts, signals puzzles, deception tricks, labs, terminals and incidents are all
challenges on the same track list, and earn the same XP. The phishing basics come first. The
technical labs sit further along, unlocked as the player progresses (section 5a).

## 2. Assessment of the review suggestions

| Suggestion | Checked against the code | Verdict | Where it goes |
|---|---|---|---|
| **Remove predictable visual clues** | Confirmed. `Content::ShiftImport::LANDINGS` maps `bait_landing` → `credential_harvest` and `malware` → `malware_download`. Genuine portals (`_portal.html.erb`) never show a password field, and only malware shows "Open this file?". *A password box means phish* is a winning strategy today. | **Adopt, top priority.** It breaks the "never send hidden answers" rule through the layout instead of the data. | P2 |
| **Make verification meaningful** | Confirmed. `ShiftAttempt::Verifiable#verify_sender` is one button that "calls the sender back on a number you already hold" and returns a scripted line for 30s. The M7b staff directory exists but isn't part of verifying. There's no way to go to a portal yourself. | **Adopt.** Choosing *which* channel is the real skill. Real attackers answer the phone number they gave you. | P2 |
| **Fresh scenarios to show learning; NIST Phish Scale** | Confirmed gap: no variants, no per-technique record. Phish Scale fits what we already author: its *cues* map to red flags, and its *premise alignment* is the Workshop's `relevance` (0–3). | **Adopt.** Difficulty ratings come almost free from existing content. | P4 |
| **Give practice visible value** | Confirmed: `ShiftAttempt::Finishable#first_scored_attempt?` scores only the first attempt, including a clock-off. That *must* stay: the debrief reveals every answer, so a replay is never a fair test. | **Adopt in a different form.** Keep the first-attempt XP rule. Make practice valuable through **fresh variants** and a **mastery** record, not replays. | P4 |
| **Connect Red and Blue more closely** | Partly done: a Workshop target names its shift, and the Red debrief has a "Play Blue's side" link. What's missing is the *specific* verification step that beats each card, and a Blue round that contains the player's own attack. | **Adopt.** It's cheap and makes the Purple promise concrete. | P3 |

The review also changes two of my earlier ideas:
- **"Consequences carry forward"** (miss a phish in mission 1, mission 3 starts with the attacker
  inside) only branches *between* missions, after a debrief has already revealed everything. That
  keeps the phase 1 rule that nothing inside a shift depends on being right. See section 4.
- **Hidden text is different from landing pages.** Genuine services really do show sign-in pages and
  downloads, so those need genuine counterparts (P2). Hiding text in white-on-white or a 1px font
  has no real legitimate use. Hidden text is a red flag to find, just as it is in real life, and
  the player is credited for checking. It doesn't need a harmless twin.

## 3. Rules carried over, and the deliberate exceptions

Everything in CLAUDE.md's "Game rules that must never be broken" and "Security" still applies. Phase 2
adds:

1. **No tell in the presentation.** Every landing template, attachment type, lab screen and terminal
   output that can appear on a malicious path must also appear on a genuine one somewhere in the
   shipped content. (Hidden-content tricks are exempt: finding them *is* the skill, see section 2.) A content test checks this per template, alongside
   `Shift::LazyPlay`, which gains a "judge by the page alone" strategy that must stay under one star.
2. **Simulate, never execute.** Labs, terminals and the Workbench run on authored state machines and
   fictional data. No player input reaches a real database, shell, package index or network. A SQL
   payload is tokenised and classified, never run.
3. **Free text in labs, and only in labs.** Phase 1 has no free-text field anywhere in play. Phase 2
   allows free text in *lab inputs*: a terminal command, a form field in a target app, a decoded flag.
   - Every lab input carries the warning "Never type real passwords or personal details".
   - Capped at 200 characters, with control characters stripped.
   - Evaluated only by the simulator, and always rendered escaped.
   - Filtered from the server logs (`filter_parameters`), and never shown on public profiles or
     leaderboards.
   - Saved on the player's attempt, so their debrief can show what they typed and what it did, and
     Blue's patch can replay their real attacks. Deleted with the attempt.
   - Private-detail sharing stays chip-only, exactly as M7b.
4. **Playing against other players' attacks.** A long-term aim is a big competition where everyone's
   defences face everyone's attacks. So, unlike phase 1, an attack one player builds in a Red lab can
   be used against other players, with these safeguards:
   - **Opt-in** when the attack is submitted ("your attack may be used against other players"), and
     the author's leaderboard opt-out is honoured.
   - **Only attacks travel.** What's shared is an input the recogniser classified as an attack,
     re-rendered from its tokens and classification, never the raw text, so stray personal details
     or abuse can't reach anyone else.
   - **No spoilers.** Another player's working payload is a Red lab's answer. It's only shown to a
     player who has finished that Red stage. Before then, it's only used inside Blue's patch replay,
     with its text hidden until the debrief.
   - **Moderation.** Rendered escaped, with a "report this attack" button.
   - The competition format (seasons, credit by display name or anonymously) comes in a later
     milestone. From P5, the data model keeps each shared attack's author and their consent.
5. **A password on the persona card.** The card gains a generated, fictional password chip (this
   reverses M7b's "no password on the card"). Sign-in pages take it by picking the chip, like any other
   detail: there is still no password box to type into, so mock pages never take typed passwords. P2
   updates CLAUDE.md's security rule 5 and the M7b section of `docs/PLAN.md` to match.
6. **Answers stay on the server.** Flags, lab states, which inputs succeed, which fix holds and what
   the next turn of an incident brings are never in HTML, data attributes, JSON or Turbo Streams.
   Flags are compared server-side, in constant time, against a stored digest.
7. **Fiction only, extended.** The reserved-domain rule still applies. Nations, militaries, units,
   bases and package indexes are invented too: no real country, armed force, APT name or package
   registry. Real incidents are re-enacted by their *mechanism* ("a 2021 supply-chain attack on
   internal package names") with a short, factual "based on" note in the debrief, never with real
   companies' assets.
8. **Nothing operational.** Labs teach well-documented mechanisms at the depth of OWASP or
   PortSwigger training labs. Payloads only work against our simulator's fictional schema.
   Industrial control (OT) scenarios are decision-making ("isolate the pump controller?"), never
   instructions for real equipment.

## 4. The setting: Exercise SOGGY BISCUIT

Larkhill Finance stays as the civilian tracks. Phase 2 adds a second world, framed as a **military
cyber exercise**. Armed forces really do run red-on-blue exercises against an opposing force (OPFOR),
which gives Red a legitimate role: you're the exercise's OPFOR, not a criminal.

**Tone: light-hearted, not grim.** Think a wry exercise briefing, not a war film. The techniques are
real and taught properly, but the names are silly. Codenames come from a deliberately daft
generator (an adjective plus a household object: TRUCULENT TEAPOT, SOGGY BISCUIT, OPERATION
SENSIBLE CARDIGAN). Briefings can be dry and funny. Nobody gets hurt: the stakes are a base's
supplies, its water and its pride.

- **Blue:** the cyber defence cell at **Puffin Point**, a fictional naval station and logistics hub
  (`puffinpoint.example`), its satellite ground station, and the desalination plant that supplies it.
- **The adversary:** a cyber unit of the fictional **Grand Duchy of Grizzlemark**, codenamed **TRUCULENT TEAPOT** by
  allied analysts. It has recognisable habits: reuses a domain-naming pattern, signs its loaders the
  same way, favours one cipher family, and makes the same grammar slip in its phishing.
- **The dossier:** Blue's notebook of TRUCULENT TEAPOT's techniques, infrastructure and signatures. It
  fills from debriefs as missions are completed, so recognising "this is how TEAPOT works" becomes a
  skill that carries across missions.
- **Missions follow the stages of an attack**, one stage per mission:

  | # | Mission | Stage | Main play |
  |---|---|---|---|
  | 1 | *Quartermaster's inbox* | Initial access | Inbox shift: phishing the logistics office |
  | 2 | *Kettle chatter* | Command and control | Signals: intercepts and the Workbench |
  | 3 | *Open door* | Exploiting a public-facing app | Lab: SQL injection on the visitor booking portal |
  | 4 | *Borrowed name* | Supply chain | Lab: dependency confusion in the base's software build |
  | 5 | *Quiet exfil* | Stealing data out | Terminal: log triage, DNS tunnelling |
  | 6 | *Low tide* | Impact on control systems | Live incident: containment decisions at the desalination plant |

- **Consequences between missions, never within one.** Each mission's briefing reflects how the
  previous one went ("Because the booking portal fell in *Open door*, TEAPOT has the visitor list").
  This is allowed because the debrief has already shown the player everything. Within a mission,
  arrivals and outcomes never depend on being right. Each mission can also be started from a
  **standard start**, so nobody gets stuck. Branching uses at most two authored states per mission
  (`held` / `breached`).
- **Light military flavour:** mission briefings with a theatre map; a threat level shown *between*
  missions only, measured in biscuits; ranks as the Blue and Red level titles in this world; mission
  patches as badges (a teapot with a crack in it for *Low tide*).

## 5a. The ladder: how the challenges fit together

All challenge kinds live in the same track list and the same XP economy. Tracks unlock by tier: a
tier opens once the player has finished a set number of challenges in the tier before (set per
tier, around three). Within a tier, tracks can be played in any order. The dashboard always suggests
the next challenge. A player who has already played a track before tiers arrive keeps access to it:
tiers only ever unlock, never lock. The tiers:

| Tier | Tracks | Kinds |
|---|---|---|
| 1. Basics | Phishing Basics, Dodgy Links, Signals 1 (encodings and Caesar) | inbox, phone, signals |
| 2. Deception | Business Email Compromise, Hidden in Plain Sight (P3), Signals 2 (Vigenère, XOR) | inbox, signals |
| 3. Exercise SOGGY BISCUIT | Missions 1–3 | inbox, signals, lab |
| 4. Technical | Web labs (P5), Supply chain (P7), Signals 3 (forensics) | lab, signals |
| 5. Incident | Missions 4–6, the case-file library (P9) | lab, terminal, incident |

**XP for every challenge, on both sides.**
- Blue challenges (shifts, signals, patching labs, incidents) earn Blue XP.
- Red challenges (the Workshop *and* Red labs, such as the SQL injection and dependency-confusion
  attacks) earn Red XP and count on the Red leaderboard.
- The first-scored-attempt rule applies to every kind.

## 5. Milestones

### P1 — Signals: intercepts and the Workbench (CTF, part 1)

- **New shift kind: `signals`.** The player is a signals intelligence analyst with a queue of intercepted TRUCULENT TEAPOT traffic. Each intercept
  gives up a **flag**, which is a fact needed elsewhere in the story, such as a meeting time, a
  domain or a person's name, and not a random string.
- **The Workbench**, a CyberChef-style tool: chain operations such as base64, hex, URL decode,
  ROT-n, Vigenère with a key, XOR with a key, reverse, a frequency-analysis chart and a strings view.
  The operations run in a Stimulus controller on the ciphertext the player already has, which is
  safe because the flag is only ever checked on the server.
- **Puzzles get harder in order:**
  1. base64 or hex
  2. Caesar
  3. Vigenère with a key hidden in an earlier intercept
  4. repeating-key XOR
  5. a reused one-time pad (XOR two intercepts together)
  6. forensics: EXIF data leaking a location, a document's author metadata, steganography in an
     image's least significant bits, a packet log with data hidden in DNS subdomains
- **Scoring:** flags found, hints used (as in phase 1), and wrong submissions, which are capped and
  rate-limited so guessing doesn't pay.
- **Checking a flag:** the submission and the authored flag are normalised the same way before the
  digests are compared: Unicode NFKC, case folded, whitespace collapsed, and leading or trailing
  punctuation dropped. So "Fuel depot" and "fuel depot." both count.
- **Intercept of the day:** one daily puzzle that keeps a streak going. It earns Blue XP like any
  challenge.
- **First taste of Exercise SOGGY BISCUIT.** The intercepts introduce TRUCULENT TEAPOT and Puffin
  Point before the campaign exists. Signals 1 covers puzzle levels 1–2, Signals 2 levels 3–5 and
  Signals 3 level 6.
- **The ladder (section 5a) arrives here.** Tracks gain a `tier` and unlock as described there, and
  Signals 1 sits in tier 1 next to Phishing Basics.

**Done when:** flags are stored as digests and compared on the server; a system test decodes a
multi-step intercept with the Workbench; no plaintext or flag appears in the page; a tier-2 track
is locked until enough tier-1 challenges are finished.

### P2 — Fair play: no tells, real verification

**Landings independent of outcome**
- Separate *what a page looks like* from *what it does*. A link's `landing:` names any template, and
  its `outcome:` stays on the server. The importer drops the fixed `LANDINGS` map.
- New genuine pages:
  - the Larkhill single sign-on (SSO) page, which genuinely needs a sign-in to reach the expenses portal
  - a signed installer on the IT portal ("Open file" is the right move)
  - a document viewer
- New malicious pages:
  - a fake shared-document viewer
  - a "verify you're human" page that asks you to paste a command into Run (ClickFix)
  - an OAuth consent screen granting a lookalike app access to your mailbox
  - a payment portal that asks for bank details, not a password
  - a browser-in-the-browser pop-up with a fake address bar *inside* the page, so only the
    in-game browser's own address bar is trustworthy
- The sign-in page treats the password like any other detail (section 3, rule 5). Genuine SSO
  accepts the persona's password chip. A lookalike page records it as handed over.
- Content tests: every template is used by at least one genuine and one malicious link, and
  `Shift::LazyPlay` gains a "judge the page" strategy that must stay under one star.

**Verification is a choice of channel.** Replace "Verify sender" with **Check this**, which offers:
- **Call the number in this message.** Whoever answers reassures you: the attacker on a phish, the
  real sender on a genuine message. It costs time and teaches nothing, because the lesson is the
  channel you chose, not what you heard. Author both kinds of answer to sound alike.
- **Call someone from the directory.** Their scripted answer is the truth (`verify_result`).
- **Go to the portal yourself.** A bookmarks bar in the in-game browser opens the real portal,
  which shows whether there really is an invoice, an expired password or a new supplier waiting.
  This is the habit we most want to build.
- Every option costs the same, so the price never hints at the right one.
- **Time cost:** beginner shifts cost nothing to verify. Intermediate ones cost 15s, advanced 30s.
  The speed bonus tapers rather than steps down, so one sensible check never visibly "costs" a star.
- **Debrief credit** for "checked through a trusted channel before acting" on every high-stakes
  message (payments, credentials, details), whether it turned out genuine or not.

**Done when:** the template-pairing and judge-the-page tests pass across the shipped content; a system
test verifies through the directory and through a bookmark; no outcome, landing purpose or
`verify_result` appears in the HTML before the debrief.

### P3 — Deception tricks in the inbox, and the Red↔Blue loop

**Hidden content.** New authored tricks, each on a short importer allowlist:

| Trick | What the player sees | How Blue catches it |
|---|---|---|
| Text the same colour as the background, or a 1px font | Nothing | Select all, or **View raw** |
| Zero-width characters splitting a keyword | A normal word | View raw shows `pass​word` with markers |
| Homoglyph domain (Cyrillic а) | `lаrkhill.example` | The hover popup flags mixed scripts as Punycode `xn--…` |
| Right-to-left override in a filename | `invoice‮fdp.exe` shows as `invoiceexe.pdf` | Attachment details show the real extension |
| HTML comment carrying instructions | Nothing | View raw |
| **Prompt injection against the AI assistant** | A tidy summary that recommends "forward the duty roster to the auditor" | **Show what I read** reveals the hidden instruction |

- **The AI briefing assistant** is a scripted, fictional assistant on the play screen that summarises
  an email when asked. Its summaries are authored. An injected message's summary has been "hijacked",
  and the debrief explains prompt injection. It never calls a real model. Genuine summaries recommend
  actions too ("reply to confirm the slot"), so a summary telling you to do something is never the
  tell by itself.
- **View raw** and **Select all** are free and offered on every message, so using them hints at
  nothing.
- **Hidden content is always a red flag.** It has no legitimate use in the game, as in real life.
  Each trick is authored as a red flag on the message. Finding and flagging it earns the usual
  flag points, and the debrief praises the check ("You selected the text and found the instructions
  hidden in white").
- The CSP blocks inline styles, so tricks are importer-allowlisted Tailwind classes (hidden-colour
  text, tiny text) with neutral names. They're in the HTML, but that's fine: looking at the source
  is exactly the skill being taught. The importer strips `class` today, so P3 adds an explicit list of
  allowed classes.
- Homoglyph domains need a Punycode rule in `Content::ReservedNames` (the encoded host must still be
  under a reserved domain). Zero-width and right-to-left characters are tested against the
  character counting shared by the browser and the server (from #20), so flags and notes still land.
- New techniques: T1027 (obfuscation), T1036.002 (right-to-left override), a prompt-injection
  technique, and homoglyph lookalike domains under T1583.001.

**Red→Blue loop**
- Each Workshop card gets a `beaten_by:` naming the specific move that defeats it ("Calling Pellow
  Clarke on the directory number", "Going to the payroll portal yourself"). The Red debrief shows it
  per bot.
- After a Workshop launch, offer **"Your attack, from the other side"**: a short Blue round on the
  target's shift with *the player's own email* inserted among the genuine mail. The email is
  assembled from the chosen cards' pre-written text, so it's safe. It's practice only (no XP), and
  its debrief shows the step that would have stopped it.
- The Blue debrief links each phish to the Workshop target that teaches building it.

**Done when:** the importer rejects tricks outside the allowlist; a system test reveals hidden text with
View raw and flags it for points; the Red debrief lists
`beaten_by`; the Red→Blue round plays and awards no XP.

### P4 — Mastery and fresh variants

- **Scenario families.** A shift can declare `variant_of: <slug>` and the techniques it re-tests,
  with different wording, people and circumstances. Each family needs at least three variants
  before it's published.
- **Mastery per technique and side**, recorded per user:
  - phish reported
  - genuine work done
  - false positives
  - compromises
  - trusted-channel checks

  The profile and dashboard show a mastery grid. A missed technique schedules a fresh variant that
  re-tests it ("You missed a changed-bank-details scam on Tuesday. Here's another one").
- **XP rules unchanged** for competition: the first scored attempt per shift. Each *variant* is its
  own shift, so practice on a fresh variant does earn XP and leaderboard points, and replaying a
  seen shift earns mastery only, marked "practice".
- **Difficulty from the NIST Phish Scale.** Each phish gets a rating from its **cues**, counted
  from its red flags and grouped into Phish Scale categories, and its **premise alignment**,
  authored 0–3 as in the Workshop's `relevance`. That gives *least*, *moderately* or *very
  difficult*. The debrief shows it, mastery weights by it, and the variant picker climbs it.
- **Measures in the debrief:** reporting accuracy, false-positive rate, and genuine work completed.
  These are separate numbers, not one score, so being paranoid shows up as clearly as being careless.

**Done when:** the importer validates families and Phish Scale fields; mastery updates are unit-tested;
a system test misses a technique and is offered a variant of it; replaying a seen shift earns no XP.

### P5 — The Lab engine and the first case file: SQL injection (CTF, part 2)

**The Lab engine**
- A lab is an authored state machine: **screens** (a fictional web app in the in-game browser, or a
  terminal), **inputs** (free text, within the limits in section 3), and **recognisers** that
  classify each input and move the lab to its next state.
- `ShiftAttempt` gains lab concerns, such as `ShiftAttempt::Exploiting` and
  `ShiftAttempt::Patching`. Every input is a POST recorded as an `AttemptAction`, as now.

**Case file: *Open door*, the visitor booking portal at Puffin Point**
- **Red, three stages.** After every attempt the screen shows **the query the server built**:
  1. Bypass the sign-in. `name = '' OR '1'='1' --` is recognised as a tautology after
     breaking out of the string.
  2. A UNION query that pulls the fictional `visitors` table. The column count has to be right,
     and errors teach it.
  3. Blind injection: a yes/no page that leaks one character at a time, with a scripted helper so
     it isn't tedious.
- **How the simulator works.** A small SQL tokeniser places the input inside the authored query
  template, checks whether it broke out of the literal and what it added (tautology, comment,
  UNION, stacked query), and answers from a fictional dataset in the YAML. It never connects to a
  database.
- **Blue, the mirrored half: "patch the portal".** Read the vulnerable controller code and choose
  a fix:
  - a parameterised query, which holds
  - escaping quotes, which fails on a numeric field
  - blocking "OR" and "UNION", which fails against case changes and `||`
  - a stored procedure that concatenates inside, which fails
  - a WAF rule, which only partly holds

  Then **replay**: the player's own saved Red payloads, other players' shared attacks (section 3, rule
  4) and a canned set run against the chosen fix, and the player watches the bad fixes fall. That
  replay is the Purple moment.
- New techniques: T1190 (exploit a public-facing app).
- **XP:** the Red half earns Red XP and the Blue half earns Blue XP, first scored attempt only.

**Done when:** the tokeniser and recognisers are unit-tested against a payload corpus, including
harmless inputs that contain quotes; a system test completes the Red sign-in bypass and the Blue
patch-and-replay; no lab state or accepted pattern reaches the browser.

### P6 — Exercise SOGGY BISCUIT: the campaign

- A **Campaign** model is an ordered list of missions, each pointing at a shift of any kind (inbox,
  signals, lab, terminal, incident), with between-mission state (`held` / `breached`) and
  briefings for each state.
- The **dossier**: entries unlocked by debriefs, each linked to techniques and the TRUCULENT TEAPOT
  calling cards they teach.
- Missions 1–3 use P1–P5 content in the new setting: the quartermaster's inbox, Kettle chatter
  (signals) and Open door (SQL injection). Missions 4–6 arrive with P7–P8.
- **Military flavour:** a theatre map, rank titles, mission patches, and the threat level between
  missions.
- This picks up section 11.4 of `docs/PLAN.md` (one attacker per track, facts carried across
  shifts). The rule against branching on results is kept *within* a mission and relaxed
  *between* missions, for the reason in section 4.

**Done when:** a system test plays missions 1–3 through both branches; a mission's briefing reflects
the previous result; a standard start works.

### P7 — Case file: *Borrowed name* (dependency confusion)

This is based on the 2021 dependency-confusion research, re-enacted with a fictional package index,
**PyPkg** (`pypkg.example`).
- **Red:**
  1. Recon finds an error page whose stack trace names an internal module, `pp_logistics`, or an
     exposed `/.git/` with a `requirements.txt`.
  2. A PyPkg search shows the name is unclaimed.
  3. Build the package from **cards**, not code: an install hook that sends a DNS callback, and a
     choice of version number. Free text, and it must beat the internal `1.4.2`: picking `99.0.0`
     teaches how pip resolves versions.
  4. Publish.
  5. Wait for the base's nightly build, and catch the callback with the build host's name.
- **Blue, preventing it:** review the build's `pip.conf` and CI config, and choose fixes:
  - `--index-url` instead of `--extra-index-url`
  - pinned hashes
  - reserving the name on PyPkg
  - a scoped private registry

  Then replay Red's attack against the config.
- **Blue, mid-attack (incident mode, see P8):** a build log shows `pp-logistics 99.0.0` fetched
  from PyPkg. Rotate the CI secrets, quarantine the build artefacts, search outbound logs for the
  callback, and tell anyone downstream. Order and speed both count.
- New techniques: T1195.001 (supply-chain compromise of software dependencies).

**Done when:** all three halves play end to end in system tests; the version-resolution recogniser is
unit-tested.

### P8 — Terminal, log triage and live incident

**Terminal**
- A simulated shell over an authored fictional filesystem and logs. It accepts an allowlist of
  commands: `ls`, `cd`, `cat`, `less`, `head`, `tail`, `grep` (with a few flags), `wc`, `sort`,
  `uniq`, `whoami`, `history`, `base64 -d` and `dig`.
- It's parsed and answered entirely on the server. Unknown commands get `command not found`.
- **Mission 5, *Quiet exfil*:** find the base64 chunks in DNS query logs, decode them, identify what
  left the network, and block the domain.

**Live incident (turn-based)**
- An attack graph of fictional hosts. Each turn TRUCULENT TEAPOT advances along its authored plan, and
  Blue picks one or two containment moves (isolate a host, disable an account, kill a process,
  block egress, restore from backup), each with an operational cost: "isolating the pump controller
  stops fresh water for the base".
- The adversary's plan never depends on Blue's earlier *correctness* in ways the screen reveals.
  It only reacts to what Blue's containment physically blocks, which Blue already knows.
- **Mission 6, *Low tide*:** ransomware moves from IT into the desalination plant's control
  network. The skill is containing the attack without causing the outage yourself.

**Done when:** the command parser and the attack-graph turns are unit-tested; a system test triages
the exfil and contains the incident.

### P9 — Case-file library

Each case file is a mirrored Red/Blue lab based on a real incident's mechanism, written as content
on the P5/P8 engines. In rough order:

| Case file | Mechanism | Technique |
|---|---|---|
| *Push, push, push* | MFA fatigue, then a call from "IT" (2022) | T1621 |
| *Old password* | A reused VPN password on an account without MFA (2021) | T1078 |
| *Factory settings* | Default credentials on a perimeter camera; botnet recruitment | T1078.001 |
| *Header trouble* | A JNDI lookup in a User-Agent header reaches the logger (2021) | T1190 |
| *Patient maintainer* | A years-long social-engineering campaign against an open-source maintainer (2024). Blue reads the mailing list and spots the pressure campaign | T1195.001 |
| *Paste this* | ClickFix: a fake CAPTCHA asks you to paste a command | T1204.004 |
| *Let me in* | OAuth consent phishing | T1528 |
| *Spoofed sky* | GPS spoofing of a drone's navigation (decision-based) | — |
| *Open bucket* | A storage bucket left public, and an insecure direct object reference (IDOR) in a booking API | T1530 |

## 6. Data model additions (sketch)

```
Track                    gains: tier (int), unlock_after (count of challenges in the tier before)
Shift                    kind gains: signals / lab / terminal / incident; side (blue/red) for labs
                         gains: variant_of_id, phish_scale (jsonb per message), campaign fields below
Message                  gains: premise_alignment (0–3), tricks (jsonb, allowlisted)
Link                     landing (template, now independent of outcome)
DirectoryEntry / Bookmark  (from M7b's directory: who answers truthfully; which portals are bookmarked)
Intercept                shift_id, key, ciphertext/artefact, flag_digest, hints
Lab                      shift_id, screens (jsonb), recognisers (jsonb), dataset (jsonb), fixes (jsonb)
Campaign / Mission       campaign_id, position, shift_id, briefings by prior state (held/breached)
CampaignProgress         user_id, campaign_id, mission states
DossierEntry / UserDossierEntry
SharedAttack             author (user_id), lab shift, stage, recognised tokens/classification (never raw
                         text), consent_at, reports_count; hidden from players who haven't finished
                         that Red stage
TechniqueMastery         user_id, technique_id, side, reported, done, false_positives,
                         compromises, trusted_checks, weighted_score
WorkshopCard             gains: beaten_by
AttemptAction            kinds gain: check_via_message / check_via_directory / open_bookmark /
                         view_raw / ask_assistant / workbench_submit / lab_input / apply_fix /
                         run_command / contain
```

Every new move is its own resource controller with a one-line `create`. Every new behaviour lives on
the models as concerns (`ShiftAttempt::Decoding`, `::Exploiting`, `::Patching`, `::Containing`), and
plain objects are nouns (`Lab::Query`, `Lab::Recogniser`, `Intercept::Workbench`).

## 7. A case file in YAML (sketch)

```yaml
slug: open-door
title: "Open door"
kind: lab
campaign: soggy-biscuit
mission: 3
based_on: "SQL injection in a public booking form, a top web-app weakness for two decades."

app:
  url: https://visitors.puffinpoint.example/sign-in
  query: "SELECT id, name FROM staff WHERE name = '{name}' AND pin = '{pin}'"
  dataset:
    staff:    [[1, "duty.officer"], [2, "gate.clerk"]]
    visitors: [[1, "R. Ashby", "Tue 0900", "Pier 3"], [2, "M. Okon", "Tue 1100", "Fuel depot"]]

red:
  stages:
    - key: bypass
      goal: "Get past the sign-in without a PIN."
      accepts: { breaks_literal: true, adds: [tautology], comments_rest: true }
    - key: union
      goal: "List tomorrow's visitors."
      accepts: { adds: [union], columns: 2, table: visitors }
      flag: "Fuel depot"   # stored as a digest on import

blue:
  code: |
    def sign_in
      Staff.find_by_sql("SELECT id, name FROM staff WHERE name = '#{params[:name]}' AND pin = '#{params[:pin]}'")
    end
  fixes:
    - { key: f1, label: "Pass the values as bind parameters", holds: true }
    - { key: f2, label: "Escape single quotes in the input", holds: false, beaten_by: numeric_field }
    - { key: f3, label: "Reject input containing OR or UNION", holds: false, beaten_by: case_and_pipes }
    - { key: f4, label: "Add a WAF rule for common payloads", holds: partial }
  replay: [red_payloads, canned]
```

## 8. Decisions (agreed 2026-11-16)

1. **Order:** signals come first (P1) for an early "wow". The fairness and learning work follows
   in P2–P4.
2. **Tone:** a fictional exercise that doesn't take itself too seriously. Codenames are
   light-hearted (section 4).
3. **Audience:** one game. The labs are challenges on the same ladder, further along than the
   phishing basics (section 5a), not a separate product.
4. **Free text is allowed in labs, with a warning** (section 3, rule 3). What a player types (a SQL
   payload, a terminal command) is saved on their own attempt, so their debrief can show "you typed
   this, and here's the query it built".
5. **Red labs earn Red XP** and count on the Red leaderboard, alongside the Workshop.
6. **Hidden text is always malicious** in the game, as in real life. Spotting it is credited, and it
   needs no harmless counterpart (section 2).
7. **Players' attacks can be played by other players**, building towards a big competition, with the
   safeguards in section 3, rule 4.
8. **A password on the persona card** is fine: a generated chip, never typed (section 3, rule 5).
