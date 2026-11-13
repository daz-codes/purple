# Purple

A Red v Blue social-engineering training game.

- **Blue** works a *shift*: an inbox (or a phone) full of messages to deal with. Reply to the ones that
  need a reply, do what the genuine ones ask, archive what needs nothing, and report Red's phishing.
- **Red** builds a phishing email from technique cards in *Red's Workshop* and launches it at a panel
  of simulated Blue bots.
- Every round ends with a **Purple debrief** that replays both sides' moves, mapped to MITRE ATT&CK.

All companies, people and domains in the game are fictional, and only reserved domains
(`example.com`, `.example`, `.test`, `.invalid`) are used.

## Requirements

- Ruby 3.4 (see `.ruby-version`; `mise.toml` is provided for mise users)
- PostgreSQL 16 or newer
- Google Chrome (for system tests)

## Setup

```sh
bin/setup      # installs gems, prepares the database, starts the dev server
bin/dev        # later runs: Rails + Tailwind watcher on http://localhost:3000
```

In development, sent emails open in your browser via letter_opener.

## Tests and checks

```sh
bin/rails test           # unit and integration tests
bin/rails test:system    # browser tests (headless Chrome)
bin/ci                   # rubocop, bundler-audit, importmap audit, brakeman and all tests
```

GitHub Actions runs the same checks on every push and pull request (`.github/workflows/ci.yml`).

## Playing a shift

Pick a track at `/tracks`, read a shift's briefing and start it. The play screen shows your inbox
(or, for a messages shift, a phone) and the open message. Every move (reading a message, showing full
headers, calling the sender back, flagging, replying, archiving, reporting, clocking off early) is a POST to its
own small controller, which calls a method on the `ShiftAttempt` (`attempt.report(message)`). The
attempt logs the move as an `AttemptAction` with the time it was made, and the panes update by Turbo
Stream.

There's no task list, clock or score on screen. More messages arrive as you deal with others
(`ShiftAttempt::Arrivals`), and the shift ends when every message has been reported or archived, or
when you clock off early. Time is real time, kept on the server (a call-back adds 30 seconds). Clearing
the inbox earns a speed bonus against the shift's target time, scaled by how many messages you handled
as expected, unless you've turned on relaxed mode on your account page. `ShiftAttempt::Scorecard`
scores the log, and everything is revealed in the Purple debrief.

Links and attachments open in an in-game browser (`ShiftAttempt::Browsing`). It shows the link's real
address, and the server picks the page: a portal where you do what a genuine message asks, a harmless
article, a lookalike sign-in page or a download prompt. Signing in on a lookalike page or running a
download compromises you (`ShiftAttempt::Compromisable`), but nothing says so until the debrief: a
submitted sign-in page shows the same plain confirmation a real portal does. The lookalike page's
fields have no names, so nothing typed is ever sent.

## Content authoring

All game content is YAML in `content/`:

```
content/
  techniques.yml               the technique vocabulary, mapped to MITRE ATT&CK
  badges.yml                   badges players can earn
  tracks/<track>/_track.yml    a track's title, description, position and difficulty
  tracks/<track>/<shift>.yml   one file per shift (the file name is the shift's slug)
```

Load it with:

```sh
bin/rails content:import              # also runs as part of bin/rails db:seed
CONTENT_DIR=path/to/content bin/rails content:import
```

The import runs in one transaction and is idempotent: records are upserted by key or slug, children
removed from a file are deleted, and shifts or tracks whose files have gone are unpublished (not
deleted, so players' history survives). If anything is wrong, nothing is changed and the error names
the file and the exact place, for example:

```
content/tracks/phishing-basics/month-end-at-larkhill.yml: messages[1] (fake_invoice) → links[0]:
  outcome must be one of bait_landing, malware, harmless for phishing messages (got portal)
```

### Writing a shift

`content/tracks/phishing-basics/month-end-at-larkhill.yml` is a complete example. Each message has a
`body_html`, a list of `links` rules (`match` is a substring of the href), and:

- **When it arrives:** `arrives: start` (the default), `arrives: { after_handled: 2 }` (once any two
  messages have been dealt with) or `arrives: { after: real_invoice }` (a follow-up). Triggers only
  depend on *that* messages were dealt with, never on whether the player was right.
- **For a genuine message, what it expects:** `expects: reply` (send a `safe` canned reply), `act` (press the button on its one `portal` link, whose rule has an `action:` label) or
  `archive` (nothing to do); its `points`; and optionally `urgent_within_minutes`.
- **For a phishing message:** `techniques` and `red_flags`. A phish always expects a report. It can
  say which genuine message it copies (`imitates: real_invoice`); it must then arrive at the start or
  on exactly the same trigger, so the player has to choose between them rather than spot a late
  duplicate.
- Optional `replies:` (2 to 4, each `text`, `outcome`: `safe`, `poor` (genuine only), `compromise`
  (phishing only) or `verify`, and an optional `response`).
- **Read it, you'll need it later.** Facts set up early should pay off later, so the player has to
  read everything:
  - A red flag can say which genuine message it contradicts:
    `contradicts: { message: it_welcome, quote: "we will never ask for your current password by email" }`.
  - A genuine message that asks a question can say where its answer was:
    `answer_in: { message: hr_onboarding, quote: "2pm in the Harbour Room" }`. It must expect a reply and
    offer a wrong answer (`poor`) among its replies.
  - The quote must appear exactly once in the other message, and that message must always be in the
    inbox first (at the start, or the dependent message arrives `after:` it). `contradicts` must name a
    genuine message. `answer_in` may name a phish only if the question arrives last
    (`after_handled:` every other message). The debrief shows both; neither reaches the page mid-shift.

The importer enforces these rules:

- **Fiction only.** Every URL, email address and host name, in links, addresses and text, must be on
  `example.com`, `example.net`, `example.org` or under `.example`, `.test` or `.invalid`. Phone numbers
  must be Ofcom drama numbers (`07700 900000`–`07700 900999`). Any dotted name counts as a host
  except file names such as `Invoice.pdf` (but not `.zip` or `.mov`, which are real top-level domains).
  No real brands: names in `Content::ReservedNames::REAL_BRANDS` are rejected anywhere players can
  see them, including SMS sender IDs. The list can't be complete, so reviewers still check.
- **Safe HTML only:** `p br strong em b i u ul ol li blockquote h3 h4 hr small` and `<a href>`. No
  scripts, styles, images, comments or other attributes. In particular, **don't add `id` or `data-*`
  attributes**: the importer gives every paragraph-like element a neutral anchor (`p1`, `p2`…), every
  link `l1`, `l2`… and every attachment `a1`, `a2`…, so nothing in the page hints at the answer. Body
  anchors are stored as `data-anchor` attributes rather than DOM ids, since every message has a `p1`.
- **Red flags** are either a whole part (`anchor:` `from`, `to`, `reply_to`, `subject`, `l1`, `a1`…) or
  a phrase in the body (`quote: "within 1 hour"`, plus `in: p2` if the words appear in more than one
  paragraph). A quote must appear exactly once, inside one sentence. Text is matched as the player
  sees it, with whitespace runs counted as one space. The importer also splits each paragraph into sentences
  (`p1s1`, `p1s2`…) so players can flag a sentence or highlight just the words. Texts and chats only
  have `from` as a header, since that's all the phone shows.
- **Channels match the shift:** an `inbox` shift holds only emails, a `messages` shift only `sms` and `chat`.
- **Links never navigate.** Each `<a>` becomes a `<span>` carrying its key and URLs; the outcome
  (`portal`, `harmless`, `bait_landing`, `malware`) stays on the server. Every link must match exactly
  one rule, and every rule at least one link.
- **Genuine messages can't contain bait or malware**, techniques or red flags; phishing messages can't
  have portals, points or expectations.
- **Every message can arrive:** at least one arrives at the start, `after:` names another message, and
  dealing with everything that arrives must eventually bring the rest (no loops).
- **If a genuine message has a follow-up, so does at least one phish** (the attacker chasing), so a
  follow-up never shows which message was genuine.
- **Lazy play never pays:** reporting everything, archiving everything, clocking off at once, and
  flagging every sentence then reporting everything must each score below one star
  (`Shift::LazyPlay`).
- Every shift has at least one phishing message.

## Deployment

_Coming in M10: Kamal 2 to a single VPS, with Thruster in front of Puma._

See `CLAUDE.md` for project conventions and security rules.
