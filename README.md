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

## Content authoring

_Coming in M2: shifts are written as YAML in `content/tracks/<track>/<shift>.yml` and imported with
`bin/rails content:import`._

## Deployment

_Coming in M10: Kamal 2 to a single VPS, with Thruster in front of Puma._

See `CLAUDE.md` for project conventions and security rules.
