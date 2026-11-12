# Purple

A Red v Blue social-engineering training game.

- **Blue** works a *shift*: a simulated working day with an inbox, a task list and a clock. Complete
  your tasks through the legitimate emails and catch Red's phishing along the way.
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

Pick a track at `/tracks`, read a shift's briefing and start it. The play screen has the clock and
two meters along the top, then your tasks, your inbox and the reading pane. Every move (opening a
message, showing full headers, calling the sender back, reporting phishing, waiting for new mail) is a
POST to the server, which logs it as an `AttemptAction`, moves the in-game clock on and sends back
Turbo Stream updates. `Shift::Engine` applies the rules; `Scoring::Calculator` scores the log.

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
content/tracks/phishing-basics/month-end-at-contoso.yml: messages[1] (fake_invoice) → links[0]:
  outcome must be one of bait_landing, malware, harmless for phishing messages (got completes_task)
```

### Writing a shift

`content/tracks/phishing-basics/month-end-at-contoso.yml` is a complete example. Each message has a
`body_html`, a list of `links` rules (`match` is a substring of the href), and for phishing messages
`techniques` and `red_flags`.

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
- **Red flag anchors** use those neutral anchors, or `from`, `to`, `reply_to` and `subject`.
- **Links never navigate.** Each `<a>` becomes a `<span>` carrying its key and URLs; the outcome
  (`completes_task`, `harmless`, `bait_landing`, `malware`) stays on the server. Every link must match
  exactly one rule, and every rule at least one link.
- **Every task is completable by exactly one link in a legitimate message.** Phishing messages can't
  complete tasks; legitimate ones can't contain bait or malware, techniques or red flags.
- Every shift has at least one phishing message, and tasks and messages fit inside the time budget.

## Deployment

_Coming in M10: Kamal 2 to a single VPS, with Thruster in front of Puma._

See `CLAUDE.md` for project conventions and security rules.
