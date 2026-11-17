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

Each attempt gives you a persona (`ShiftAttempt::Identified`): a staff number, extension, memorable word
and security answer generated for that attempt, plus a staff directory and an authenticator that shows
an MFA code once a sign-in page asks for one. Some genuine jobs need these details and some phishes want
them. You hand them over by picking chips, never by typing: in a message's "Send details" box, or in the
fields of a portal or lookalike page (`ShiftAttempt::Sharing`). You can save words from a message as a
note to share later (`ShiftAttempt::Notable`), and ask "Why do you need this?" before deciding. The
debrief scores what you shared by its sensitivity and ends with "What Red now knows".

## Red's Workshop

Pick a target at `/workshop`: one of Blue's fictional companies, with a recon brief and a budget. Build
an email by picking one card per slot (the story, the sender, the lure, what's behind it, and the
timing), then launch it at the Blue bots. Every card is pre-written, so nothing built here works
outside the game.

`RedCampaign::Simulation` judges the email: a pure function of the cards, the bots
(`content/bots.yml`) and a seed stored on the campaign, so a launched campaign always replays the same
way. Each bot may spot the sender, story or timing (and report it, or check first), or click and then
spot the lure or payload (a near miss), or be fooled. Red scores +40 per bot fooled, +15 per near
miss and +1 per unit of budget left. The balance rules are tests on the shipped content
(`test/models/red_campaign/balance_test.rb`).

## Progression

Each side has its own XP and level. Finishing your first scored attempt at a shift earns its score as
Blue XP; launching your first scored campaign at a target earns Red XP. The first shift or campaign
each day (London time) adds a 10 XP bonus and extends your streak. Every XP gain is an `XpEvent` in
an append-only ledger, written together with the side's total and level (`User::Progression`); level
n needs `100 * (n - 1)^1.5` XP.

When a player finishes a shift or launches a campaign (`Rewarded`), `AwardBadgesJob` checks
`Badge::Rulebook` and awards any new badges (each worth 25 XP), with a toast sent by Turbo Stream.
Only confirmed players earn XP and badges. Signed-in players see a dashboard with both levels, their
streak, a side switcher, what to play next and their badges.

`/leaderboard` ranks players by XP (`Leaderboard`): Blue, Red or overall; this week (from Monday,
London time) or all time; timed or relaxed play. Ties go to whoever got there first, players can opt
out on their account page, and every player has a public profile at `/u/:display_name`.

Accessibility is checked with axe in the system tests (`assert_accessible`, WCAG 2.1 A and AA),
including a keyboard-only playthrough.

## Content authoring

All game content is YAML in `content/`:

```
content/
  techniques.yml               the technique vocabulary, mapped to MITRE ATT&CK
  badges.yml                   badges players can earn
  tracks/<track>/_track.yml    a track's title, description, position and difficulty
  tracks/<track>/<shift>.yml   one file per shift (the file name is the shift's slug)
  bots.yml                     the Blue bots that judge Red's Workshop emails
  targets/<target>.yml         one file per Workshop target: its shift, budget, recon brief and cards
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
  (phishing only), `verify` or `ask_why` ("Why do you need this?", which needs a `response`), and an
  optional `response`).
- **Who the player is** (per shift): `persona: { name, role, staff_prefix: LH, security_question }` (the
  question is answered with a name) and a `directory:` of `{ name, team, contact }`, where contact is an
  extension or a portal, never an email address.
- **Private details:** a genuine message can say what it `needs: [staff_number]` and a phish what it
  `wants:`. Card details are `name`, `role` (public), `staff_number`, `extension` (internal),
  `memorable_word`, `security_answer` (secret) and `mfa_code` (never). A message can also hold details to
  learn, quoted like a red flag: `details: [{ key: payment_codeword, label: "Payment codeword", quote:
  "BLUEBELL", sensitivity: secret, red_use: "approve fake invoices as you" }]`. A genuine `act` message
  asks for its needs in fields on its portal page; a lookalike page asks for what its phish wants.
  Optional `share_response:` is what comes back when details are sent (the same default otherwise).
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
- **Private details stay honest:** every detail asked for exists; a learned detail is always in the
  inbox before anything asks for it; secrets and the MFA code are only ever needed on a portal page
  (`expects: act`), never by reply; a message that asks for details by reply offers exactly one `ask_why`
  reply; and every `internal` detail a phish wants is needed by a genuine message, and the other way round.
- **Lazy play never pays:** reporting everything, archiving everything, clocking off at once, and
  flagging every sentence then reporting everything must each score below one star
  (`Shift::LazyPlay`). In a shift that asks for details, so must sharing everything with everyone and
  sharing whatever's asked, and sharing nothing must earn fewer stars than careful play.
- Every shift has at least one phishing message.

## Deployment

Purple runs at **https://purple.daz.codes** on the same ARM VPS as the other daz.codes apps
(`157.180.83.205`), deployed with Kamal 2 (`config/deploy.yml`):

- **The app:** Puma behind Thruster, with Solid Queue inside Puma. Each container start runs
  `db:prepare`, which creates or migrates all four databases, then `content:import`. A bad content
  file stops the new container from booting, and kamal-proxy keeps serving the old one.
- **kamal-proxy:** HTTPS with a Let's Encrypt certificate. It only routes to containers whose `/up`
  is healthy.
- **Accessories on the same server:**
  - `db`: Postgres 17, reachable only from the server.
  - `backup`: a `pg_dump` of the main database at start-up and every night at 03:00 UTC, kept on
    the server for 7 days.
  - `offsite`: rclone copies new dumps to object storage hourly and deletes ones older than 30 days.
- **The image** is built for arm64 and pushed to `ghcr.io/daz-codes/purple`, as for the other apps.

### You need

- SSH access to the server as root, and `KAMAL_REGISTRY_PASSWORD` in your shell (the same GitHub
  token the other apps use)
- A DNS A record for `purple.daz.codes` pointing at `157.180.83.205`
- An SMTP provider (Resend, Postmark, SES…) with `purple.daz.codes` verified as a sending domain.
  Emails come from `noreply@purple.daz.codes` (`MAILER_FROM` in `config/deploy.yml`), and verifying
  `daz.codes` alone doesn't cover the subdomain.
- An S3-compatible bucket for backups (Cloudflare R2, Backblaze B2, S3…) and a key that can read and
  write it. Keep the bucket private.
- An uptime monitor (Better Stack, UptimeRobot…) checking `https://purple.daz.codes/up`

### One-time setup

1. **Secrets** go in the encrypted credentials, which only `config/master.key` can open. Never commit
   that file. Run `bin/rails credentials:edit` and add:

   ```yaml
   deploy:
     database_password: <run `openssl rand -hex 32`>
     backup_access_key_id: <bucket access key>
     backup_secret_access_key: <bucket secret key>
   smtp:
     address: <e.g. smtp.postmarkapp.com>
     port: 587
     user_name: <SMTP user>
     password: <SMTP password>
   ```

   `.kamal/secrets` reads the `deploy:` values from there. The app reads `smtp:` itself.

2. **Settings** that aren't secret come from your shell, for example in a `.envrc`:

   ```sh
   export ERROR_ALERTS_TO=you@example.com                # who's emailed about production errors
   export BACKUP_S3_ENDPOINT=https://<account>.r2.cloudflarestorage.com
   export BACKUP_S3_BUCKET=purple-backups
   # export BACKUP_S3_REGION=eu-west-2                   # only if your provider needs one (default "auto")
   ```

   Kamal stops with a clear error if any of them is missing.

3. **First deploy:** `bin/kamal setup`. Docker and kamal-proxy are already on the server for the
   other apps, so this starts the three accessories, then builds, pushes and boots the app. After that,
   deploy with `bin/kamal deploy`.

### Checking it works

- **The site:** open https://purple.daz.codes, sign up, and confirm the email arrives. Then play a shift.
- **Backups:** `bin/kamal backup-logs` should show `wrote purple_production-….dump`, and
  `bin/kamal offsite-logs` should show `copied to …`. Check the file is in the bucket. Every finished
  attempt keeps a full copy of its shift's content (see `docs/CODE_STRUCTURE.md`), so dumps grow
  with play. The log line shows each dump's size, so keep an eye on it and on the bucket's 30-day
  total.
- **Errors:** production errors are emailed to `ERROR_ALERTS_TO`, at most once an hour for each
  kind of error (`ErrorAlert`). The full log is in `bin/kamal logs`.
- **Uptime:** point the monitor at `/up`. It returns 200 when the app has booted.

### Restoring a backup

Restoring overwrites the live database, so do it deliberately:

```sh
# 1. Get the dump onto the server's backup folder (skip if it's still there; dumps stay 7 days).
#    The bucket is in BACKUP_S3_BUCKET under purple/.
# 2. Stop the app so nothing writes during the restore:
bin/kamal app stop
# 3. Restore into the main database (drops and recreates its objects):
bin/kamal accessory exec backup --reuse \
  "pg_restore --clean --if-exists --no-owner --dbname=purple_production /backups/purple_production-YYYYMMDD-HHMMSS.dump"
# 4. Start the app again (it migrates if the dump is from an older version):
bin/kamal app boot
```

Restoring was tested on 2026-11-16 against Postgres 17.7: a dump taken by `config/backup/dump.sh`
restored into an empty database with its data intact. Practise it once on the real server after the
first deploy.

See `CLAUDE.md` for project conventions and security rules, and
[`docs/CODE_STRUCTURE.md`](docs/CODE_STRUCTURE.md) for concern dependencies, cache invalidation
and historical result snapshots.
