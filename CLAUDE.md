# CLAUDE.md — Purple (Red v Blue cyber training game)

The full product plan lives in `docs/PLAN.md`. Work through its milestones **in order**
(M0 → M10). Finish each one (code + tests + green CI) before starting the next, and ask before
deviating from the stack or these conventions.

## Stack (fixed)

- Ruby 3.4 (pinned in `.ruby-version` and `mise.toml`), **edge Rails** (`main`, locked by commit in
  `Gemfile.lock`), PostgreSQL 16+
- Hotwire (Turbo + Stimulus), importmap, Tailwind CSS v4 (`tailwindcss-rails`)
- Solid Queue, Solid Cache, Solid Cable
- Auth: the Rails authentication generator, extended. **No Devise.**
- Minitest + fixtures; Capybara system tests with headless Chrome
- rubocop-rails-omakase, brakeman, bundler-audit, strong_migrations
- Kamal 2 + Thruster for deployment

## Commands

```sh
bin/setup          # install gems, prepare the database
bin/dev            # web server + Tailwind watcher on http://localhost:3000
bin/rails test     # unit, model, controller and integration tests
bin/rails test:system
bin/ci             # everything CI runs: rubocop, audits, brakeman, all tests
```

Locally Postgres comes from Homebrew (`postgresql@17`). Its binaries aren't on PATH by default, but
Rails connects over the default socket, so that doesn't matter for the app.

## Code conventions

- **37signals-style Rails. No service objects**: no `app/services`, no `*Service`/`*Engine`/`*Calculator`
  doers, and no `.call` or `#perform` entry points.
  - **Behaviour lives on the models, in concerns.** A model is a slim class that includes concerns named
    for what they add, in `app/models/<model>/` (`ShiftAttempt::Timed`, `::Inbox`, `::Reportable`,
    `::Archivable`, `::Finishable`). Moves are methods on the record:
    `attempt.report(message)`, `attempt.archive(message)`, `attempt.clock_off`.
  - **Plain objects are nouns** that answer questions, under the model they serve: e.g.
    `ShiftAttempt::Scorecard` (`attempt.scorecard.total`), `Content::MessageBody.new(html).html`,
    `Content::Import.new(root).run`. Later: `RedCampaign::Simulation` rather than `Workshop::Simulator`.
- **Thin RESTful controllers.** Every move is its own resource with a `create` action of one line or
  so (`ShiftAttempts::Messages::ReportsController` → `@attempt.report(@message)`). Shared behaviour
  goes in controller concerns: `ShiftAttemptScoped`, `ShiftAttemptMessageScoped`, and `ShiftPlay`
  (the Turbo Stream response, rejections and rate limit). No dispatching on a `kind` param.
- Tests mirror the structure: one model test per concern (`test/models/shift_attempt/*_test.rb`) and
  one controller test per controller.
- Every feature ships with model/unit tests **and** at least one system test for the happy path.
- DB constraints (NOT NULL, foreign keys, unique indexes) **as well as** model validations.
- Enums are **string-backed** (`enum :status, { open: "open", ... }`), never integers.
- Migrations must satisfy strong_migrations.
- Small commits; one milestone per PR; CI green before moving on.
- Styling: Tailwind utilities plus the few shared utilities in `app/assets/tailwind/application.css`
  (`btn-*`, `card`, `form-*`). Colour tokens: `red-team`, `blue-team`, `purple-team`, `surface*`,
  `ink*`, `line`. No inline `style=""` attributes (the CSP blocks them).

## Game rules that must never be broken

- **The server is the single source of truth.** Every game action (open message, expand headers,
  verify, click link, use a portal, submit credentials, reply, flag, report, archive, use hint, clock
  off) is a POST that the server records as an `AttemptAction`, stamped with the attempt's elapsed time
  (real time plus penalties, measured only on the server). The client never computes the score, the
  time, what arrives next or the outcome.
- **Never send hidden answers to the browser** before the debrief: no `legit` flags, what a message
  expects or is worth, arrival triggers, red flags or their quotes, which earlier message a red flag
  contradicts or a question's answer was in, link, attachment or reply outcomes,
  or technique tags in HTML, data attributes, JSON or Turbo Streams. System tests assert this.
- The browser refers to messages only by `ShiftAttempt#message_ref`, an opaque HMAC of the attempt
  token and message key that's stable across content re-imports and different in every attempt, never
  by their authored `key` (`fake_invoice` would give the answer away). Nothing on the play screen says
  how the player is doing: no meters, no clock, no compromise alerts. It all waits for the debrief.
- Anti-cheat: attempts are created server-side with a random token; actions must reference an open
  attempt owned by the current user; XP only for the first scored attempt per shift/target; actions on
  a finished or expired attempt are rejected.

## Security (this is a security product — be exemplary)

1. Authored email bodies are sanitized **on import** with a strict allowlist
   (`Rails::HTML5::SafeListSanitizer`: basic formatting, `data-*`; no scripts, styles, event
   handlers or external images) and rendered inline in a scoped container (no iframe).
2. Fake links never navigate: on import every `<a>` becomes a
   `<span data-controller="fake-link" data-link-key=… data-display-url=… data-actual-url=…>`.
   No real `href` reaches the browser. Clicking POSTs the link key; the server decides what happens.
3. The importer assigns **neutral ids** (`p1`, `l1`, `a1`…) to every paragraph, link and attachment
   (as `data-anchor`, not DOM `id`, because they repeat across messages);
   descriptive ids are rejected.
4. **Fiction only:** reserved domains (`example.com`, `.example`, `.test`, `.invalid`) and invented
   companies. The importer rejects any other URL. No real brands.
5. Mock login pages never collect anything: the server records only *that* a password was submitted,
   never what was typed. Placeholder: "Never enter a real password".
6. Strict CSP with per-request nonces and `frame-ancestors 'none'`
   (`config/initializers/content_security_policy.rb`), `force_ssl`, secure cookies.
7. Rails 8 `rate_limit` on sessions, registrations, password resets and game actions.
8. Brakeman and bundler-audit must pass.
