# Phase 1 MVP Plan — Red vs Blue Cyber Training Game

> Hand this file to Claude Code. Work through the milestones **in order**. Finish each one (code + tests + green CI) before starting the next. Ask before deviating from the stack or the conventions below.

## 1. Product summary

A gamified web app built around a **Red team vs Blue team** premise. Red (the attacker) crafts social-engineering attacks; Blue (the defender) has to catch them while still getting their job done. Every round ends with a **Purple debrief** that replays both sides' moves.

**Players can play on either side and find out which they prefer.** Each side has its own XP, level and leaderboard.
- **Blue (main MVP mode):** play **shifts**. A shift is one round: a simulated working day with an inbox, a task list with deadlines and an in-game clock. The attacks in it are hand-authored scenarios, presented as "Red's campaign".
- **Red (simple MVP mode): "Red's Workshop."** Build a phishing email from technique cards on a budget, aimed at a shift's fictional company. A panel of simulated Blue bots then judges it. There's no human opponent yet.

Multiplayer, where Red's campaigns are played by real Blues, comes later (section 11). The data model is built for it now.

### The core mechanic: a working day, not a quiz

Blue can't win by avoiding every link. Each round is a **shift**: an inbox of several emails plus a **task list** with deadlines (pay a supplier invoice, sign an HR form, reset a password through the IT portal). Tasks can **only** be completed by clicking the correct link in a legitimate email. Red's phishing emails imitate those same tasks.

- **In-game clock:** each shift has a time budget (e.g. 30 in-game minutes). Reading is free; checking things costs time: expanding full headers (1 min), calling the sender back on a known number (5 min), asking IT (5 min). Hovering a link to see its real URL is free, as it is in real life.
- **Two meters:** **Productivity** (tasks done on time) and **Security** (no bait clicked, no credentials entered). The shift score combines both, so being paranoid costs you and so does being careless.
- **In-game browser:** clicking any link opens a mock browser window *inside the app*, with a fake address bar showing the actual (fictional) URL. Legitimate links open a mock portal where the task completes. Bait links open a lookalike page. If Blue notices the address bar and closes it, that's a **near miss** (small penalty). Entering credentials or opening the attachment means **compromised** (big penalty).
- **Reporting:** Blue can "Report phishing" on any email. Correct reports score; reporting a legitimate email costs points and wastes time, because the task in it stays undone.
- **Purple debrief:** after the shift, a timeline shows Red's techniques (mapped to MITRE ATT&CK), what Blue caught, what Blue missed, and where Blue spent time.

### In scope
- Sign up, log in, password reset, email confirmation
- Tracks (e.g. "Phishing Basics", "Business Email Compromise", "Dodgy Links") made up of **shifts**
- Shift type 1: **Inbox shift**. 3–8 emails, a task list, the clock, the in-game browser, flagging and reporting.
- Shift type 2: **Message shift**. The same mechanics with SMS and chat messages (smishing, fake IT support chat). The engine is reused, only the presentation differs.
- Red-flag spotting inside emails for bonus points, as before
- **Red's Workshop:** build a phishing email from technique cards and get it judged by simulated Blue bots (section 6b)
- Choose your side at onboarding and switch any time from the dashboard
- Purple debrief with the action timeline
- Scoring, XP ledger, levels, daily streaks, badges, weekly and all-time leaderboards
- Profile page; content authored as YAML and imported via a rake task
- Deployment with Kamal

### Out of scope (later phases)
Free-form Red campaigns, multiplayer, AI-generated attacks, organisations and teams, billing, admin CMS UI, real phishing campaigns, live labs, SSO.

## 2. Stack (fixed)

- Ruby 3.4+, **Rails 8**, PostgreSQL 16+
- Hotwire (Turbo + Stimulus), importmap, **Tailwind CSS** (`tailwindcss-rails`)
- Solid Queue, Solid Cache, Solid Cable
- Auth: **Rails 8 authentication generator**, extended with sign-up and email confirmation. No Devise.
- Tests: **Minitest** + fixtures, Capybara system tests (headless Chrome)
- Quality: `rubocop-rails-omakase`, `brakeman`, `bundler-audit`, `strong_migrations`, run in GitHub Actions CI
- Email: Action Mailer (letter_opener in dev; Postmark or SES in prod)
- Deploy: **Kamal 2** to a single VPS, with Thruster in front of Puma
- Error tracking: Honeybadger, AppSignal or Sentry (choose at M10)

## 3. Conventions for Claude Code

- Keep to Rails conventions, 37signals style: RESTful controllers (each game move is its own resource), and behaviour on the models in concerns (`ShiftAttempt::Reportable`, `ShiftAttempt::Clocked`…). No service objects; plain Ruby objects are nouns under their model (e.g. `ShiftAttempt::Scorecard`). *(Changed during M3: originally `Shift::Engine` and `Scoring::Calculator`.)*
- Every feature ships with model and unit tests plus at least one system test for the happy path.
- **The server is the single source of truth.** Every game action (open email, expand headers, verify, click link, submit credentials, report, complete task) is a POST that the server records and applies to the clock. The client never computes the score, the clock or the outcome.
- **Never send hidden answers to the browser:** no `legit` flags, red-flag lists, task-to-link mappings or technique tags before the debrief.
- DB constraints (NOT NULL, foreign keys, unique indexes) alongside validations. String-backed enums.
- Small commits, one milestone per PR, CI green.
- Write a `CLAUDE.md` in M0 that summarises these conventions.

## 4. Security requirements (this is a security product — be exemplary)

1. **Rendering fake emails safely.** On import, sanitize email bodies with a strict allowlist (`Rails::HTML5::SafeListSanitizer`: basic formatting tags, `id`, `data-*`; no scripts, styles, event handlers or external images). Render the stored, already-sanitized HTML inline in a scoped container (no iframe, so Stimulus can handle clicks). The strict CSP is a second layer of defence.
2. **Fake links never navigate.** On import, every `<a>` becomes `<span data-controller="fake-link" data-link-key="l3" data-display-url="…" data-actual-url="…">`. No real `href` ever reaches the browser. Clicking POSTs the link key to the server, which decides what the in-game browser shows. The actual URL is visible on hover (as in real life), but **whether a link is legit, and which task it completes, is never sent to the client**.
3. **Neutral ids.** The importer assigns ids to *every* paragraph, link and attachment (`p1`, `l1`, `a1`…), so flaggable elements don't stand out. Authors reference these ids, and descriptive ids like `flag-urgency` are rejected.
4. **Fiction only.** Content uses reserved domains (`example.com`, `.example`, `.test`, `.invalid`) and invented companies. No real brands, logos or domains. The importer rejects any URL outside the reserved set.
5. **Mock login pages never collect anything real.** The lookalike page's "password" field is a game control: the server records only that it was submitted and never stores what was typed. Display a warning in the field placeholder ("Never enter a real password").
6. Strict Content Security Policy with nonces, `frame-ancestors 'none'`, `force_ssl`, and secure cookie flags.
7. Rate limiting (Rails 8 `rate_limit`) on sessions, registrations, password resets and game actions.
8. **Anti-cheat:** a shift attempt is created server-side with a random token. Actions must reference an open attempt owned by the current user. Each user gets XP only for their first completed attempt per shift. The clock is enforced server-side, and actions after it runs out are rejected.
9. Brakeman and bundler-audit must pass in CI.

## 5. Data model

```
User
  email_address (citext, unique), password_digest, display_name (unique),
  confirmed_at, xp_total, level, current_streak, longest_streak, last_played_on,
  leaderboard_opt_out (bool), admin (bool)

Session                    (Rails auth generator)

Technique                  (seeded; the red/blue backbone)
  key (unique), name, attack_id (e.g. "T1566.002"), category (enum: pretext/sender/
  lure/payload/timing), description, defence_tip, red_cost (int), stealth (int 1–10),
  red_flag_label — e.g. lookalike_domain, display_name_spoof, reply_to_mismatch,
  urgency_pretext, credential_harvest, malicious_attachment, qr_lure, smishing

Track
  slug, title, description, position, difficulty (beginner/intermediate/advanced), published

Shift                      (one playable round, authored by Red = system for MVP)
  track_id, slug (unique), title, kind (inbox/messages), difficulty,
  time_budget_minutes, position, published, briefing (text), learning_summary (text),
  author_side (enum: red), author_type (enum: system/player — player unused in MVP)

Task                       (Blue's to-do list for the shift)
  shift_id, key, title, due_at_minute (int), points (int)

Message                    (an email or SMS/chat message in the shift)
  shift_id, key, channel (email/sms/chat), position, arrives_at_minute,
  from_name, from_address, reply_to, to_address, subject, body_html (sanitized),
  attachments (jsonb: [{id, name, type, size}]),
  replies (jsonb: [{id, text, outcome, response}], texts and chats only), legit (bool)

Link                       (every link in a message, extracted on import)
  message_id, key (e.g. l1), display_url, actual_url,
  outcome (enum: completes_task/harmless/bait_landing/malware),
  task_id (nullable — the task this link completes), landing_template (string)

RedFlag
  message_id, key, label, explanation, anchor (neutral id), points

MessageTechnique           (join) message_id, technique_id

Hint
  shift_id, position, body, penalty_percent (default 20)

ShiftAttempt
  user_id, shift_id, token (unique), status (open/completed/timed_out),
  clock_minutes (int), productivity_score, security_score, score,
  started_at, completed_at, scored (bool)
  — partial unique index on (user_id, shift_id) where scored = true

AttemptAction              (append-only event log; drives the clock, scoring and the debrief)
  shift_attempt_id, kind (enum: open_message/expand_headers/verify_sender/hover_link/
  click_link/close_landing/submit_credentials/open_attachment/report_message/
  flag_element/complete_task/use_hint), target_key, minute (int), cost_minutes (int),
  result (jsonb), created_at

XpEvent                    (append-only ledger)
  user_id, side (enum: red/blue), amount, reason (shift_completed/workshop_completed/
  streak_bonus/badge_awarded), source (polymorphic), occurred_at

User additions: preferred_side (red/blue), red_xp, red_level, blue_xp, blue_level
  (xp_total = red_xp + blue_xp)

Target                     (a Red's Workshop brief; reuses a shift's fictional company)
  shift_id, slug, title, recon_brief (text — what Red "learned": staff, tasks, suppliers),
  budget (int), position, published

TargetOption               (the cards Red can choose for this target)
  target_id, technique_id, category, label (e.g. subject line / sender address /
  link text), rendered_value (the text it puts into the email), relevance (int 0–3 —
  how well it matches the target's real tasks), extra_cost (int)

BotPersona                 (seeded Blue bots that judge Red's work)
  key, name (e.g. "Busy Bob", "Careful Carol", "New Starter Nia"), description,
  vigilance (int 1–10), detects (jsonb: technique_key → detection bonus)

RedCampaign                (one Workshop attempt)
  user_id, target_id, token, status (draft/submitted), chosen_option_ids (int[]),
  budget_spent, rendered_subject, rendered_from, rendered_body_html, results (jsonb:
  per-bot outcome and which red flag gave it away), score, scored (bool), seed (int)
  — partial unique index on (user_id, target_id) where scored = true

Badge / UserBadge          (as before)
```

## 6. Shift engine & scoring

Implement as concerns on `ShiftAttempt` (each move is a method that checks it's allowed, logs it, advances the clock and returns the logged action) and `ShiftAttempt::Scorecard` (pure function over the action log). Both must be fully unit-tested.

**Action costs (configurable per shift):** open message 0, hover link 0, expand headers 1, verify sender 5, report message 1, complete task 2, hint 0 (score penalty instead).

**Productivity score:**
- Task completed on time: `+task.points`
- Task completed late: half points
- Task never completed: `−task.points / 2`

**Security score:**
- Phish correctly reported: +30
- Legit message reported as phish: −15 (and its task is likely missed)
- Bait link clicked, then landing page closed (near miss): −10
- Credentials submitted or malicious attachment opened (compromised): −50
- Each red flag correctly flagged in a phish: `+flag.points`. Each false flag: −10, so flagging every part of a known phish costs more than it finds.

**Total** = productivity + security, minus hint penalties (`penalty_percent`% of the maximum possible score each), floored at 0. Shift star rating: 1–3 stars by thresholds, and 3 stars requires no compromise.

**XP** (Blue XP) = total score for the first scored completion only. Streak bonus (applies to whichever side you play first that day): +10 XP on the first completion each calendar day (Europe/London). Level curve: level n needs `100 * n^1.5` cumulative XP, defined in one method.

## 6b. Red's Workshop (simple Red mode)

**How a Workshop round plays:**
1. **Recon.** Red reads the target brief, e.g. "Larkhill Finance pays Tidemark invoices at month-end. Staff: Bob (busy, approves payments), Carol (security-minded), Nia (started last week)."
2. **Build.** Red picks one card per slot: **pretext** (subject and story), **sender** (lookalike domain, display-name spoof, compromised supplier), **lure** (link, attachment, QR code), **payload** (credential page, malware download) and **timing** (Monday 9am, Friday 4:55pm). Each card costs budget, and stealthier cards cost more. There's no free text: the email is assembled from the chosen cards' pre-written `rendered_value`s, so the Workshop can't produce a usable real-world phish.
3. **Preview.** Red sees the finished email exactly as Blue would.
4. **Launch.** `RedCampaign::Simulation` runs the email against each `BotPersona`. Each bot's chance of spotting each technique uses its `vigilance`, the technique's `stealth`, its `detects` bonuses and the pretext's `relevance` to the target's real tasks. The result is deterministic for the stored `seed`, so it can be replayed and tested.
5. **Purple debrief.** Per bot: fooled, suspicious (verified first) or reported, and **which red flag gave it away**. Each technique's `defence_tip` is shown so Red learns the defence too.

**Red scoring:** +40 per bot fooled, +15 per bot that clicked but closed the page (a near miss for them), 0 for reports, and +1 for each unit of budget left unspent. Spending everything isn't optimal. Red XP is awarded for the first scored campaign per target only. 1–3 stars by thresholds.

**Balance rules** (unit-tested): there's no card combination that fools every bot every time; a high-relevance pretext beats a generic one at equal cost; Careful Carol has to be fooled by cheap tricks rarely.

## 7. Milestones

### M0 — Skeleton & CI
- `rails new` (Postgres, Tailwind, importmap, Solid trifecta). Rubocop, Brakeman, bundler-audit, strong_migrations, GitHub Actions CI.
- `CLAUDE.md`, `README.md`, layout with nav and flash, responsive base styles.
- **Done when:** `bin/dev` runs and CI is green.

### M1 — Authentication
- Auth generator plus sign-up, email confirmation (24h signed token), display name, password reset, rate limits, and a sessions page (list and revoke).
- Unconfirmed users can play but earn no XP.
- **Done when:** system tests cover sign-up → confirm → log in → reset password.

### M2 — Content model & importer
- Migrations and models from section 5. Seed Techniques (≈12) and Badges.
- YAML format in `content/tracks/<track>/<shift>.yml` (see section 8).
- `bin/rails content:import` does the following:
  - idempotent upsert by slug
  - sanitizes HTML
  - assigns neutral ids to all paragraphs, links and attachments
  - extracts links into `Link` rows and rewrites them to spans
  - validates that anchors exist
  - checks every task is completable by exactly one legit link
  - rejects non-reserved domains

  It fails loudly with file context.
- Write **4 starter shifts** (3 inbox, 1 messages), each with 4–6 messages and 2–3 tasks.
- **Done when:** the import is idempotent and tested, and bad content fails with clear errors.

### M3 — Inbox shift: core play
- Track page → shift briefing ("Red's campaign targets Larkhill Finance today…") → play screen.
- Play screen: task list with deadlines (left), inbox list (middle), reading pane (right), and the clock and two meters in the header. Messages can arrive mid-shift (`arrives_at_minute`) via Turbo Stream after any action that advances the clock.
- Actions: open message, expand headers, verify sender (shows a scripted result, e.g. "Finance confirms they sent this" or "No record of this invoice"), report phishing. Every action POSTs to its own resource controller (e.g. `ShiftAttempts::Messages::ReportsController`) → a `ShiftAttempt` method → Turbo Stream updates to the clock, meters and panes.
- Shift ends when the clock runs out or the player presses "End shift". Finishing the task list doesn't end the shift or change anything else on screen, so it never hints at which of the remaining messages matter. Mail keeps arriving on its schedule; a phish that arrives after the player ends the shift early still counts as not reported. A phish that `imitates` a task must arrive no later than the genuine message for that task, so the player has to decide between them rather than spotting the fake because the task is already done.
- **Done when:** a system test plays a shift that mixes reporting a phish and leaving a legit email alone, and the engine unit tests cover the clock and deadlines.

### M4 — In-game browser & tasks
- Clicking a link opens a modal "browser" with a fake address bar showing `actual_url` and a padlock that **doesn't prove safety** (teach this in the debrief).
- Landing templates (server-rendered partials, generic styling, no real brands):
  - `portal_task`: a mock internal portal with the task action, e.g. "Approve payment £1,240". Completes the linked task.
  - `harmless`: a generic newsletter or article page.
  - `credential_harvest`: a lookalike login page. "Close tab" = near miss; "Sign in" = compromised.
  - `malware_download`: a download prompt. "Cancel" = near miss; "Open" = compromised.
- A compromise shows a short in-shift alert ("Your account just sent 400 emails…") but the shift continues, so the player feels the consequence.
- Attachments open the same way (a legit PDF preview vs an `.pdf.exe` prompt).
- **Done when:** system tests cover completing a task through a legit link, a near miss and a compromise, and confirm that page HTML contains no `legit`, `outcome` or `task_id` data.

### M5 — Red flags, hints & Purple debrief
- Flag mode inside a message: click sender, reply-to, subject, paragraphs, links or attachments to flag them (each flag POSTs).
- Hints, revealed via Turbo Stream with the penalty recorded.
- **Purple debrief** page after the shift:
  - meters and stars
  - a timeline of Blue's actions against Red's planted attacks
  - per-phish breakdown: techniques used (with ATT&CK ids), red flags found or missed, explanations
  - time spent per task
  - learning summary
- **Done when:** the debrief is rendered entirely from the action log, with tests.

### M6 — Message shift (SMS & chat)
- A phone-style UI for SMS and a chat-app style UI for fake "IT support" conversations, reusing the engine, links, browser and debrief.
- One chat scenario where "IT support" asks for an MFA code. Blue can reply with a canned choice (give code / refuse / verify via helpdesk).
- Canned replies (`replies:` in the YAML, texts and chats only, 2-4 each) get neutral ids (`r1`…) on import; each one's outcome (`safe`, `compromise`, `verify`) stays on the server, like an attachment's. There's no free text. Sending one is a `send_reply` move that keeps a copy of the reply, so re-importing content can't change an old score. `compromise` counts like entering a password on a bait page, and `verify` gets the message's `verify_result` from someone the player already trusts. Every reply costs the same, so the price never gives one away. A message shift only holds texts and chats (an inbox shift only emails), and on the phone only the sender and the body can be flagged. Genuine messages offer replies too, so having replies doesn't mark a message as the phish.
- The phone shows one screen at a time (conversation list or one conversation). There are no headers to expand and no hovering: the sender's number or chat account is all there is. Attachments are for emails only.
- **Done when:** the system test passes and the message shift is playable.

### M7 — Red's Workshop
- Models from section 5 (Target, TargetOption, BotPersona, RedCampaign). Seed 3 bot personas. Extend the importer for `content/targets/*.yml`.
- Workshop flow: target list → recon brief → card builder (slots, budget bar, live email preview via Turbo Frame) → launch → animated bot results → Purple debrief.
- `RedCampaign::Simulation` is a pure, seeded, fully unit-tested class, and the balance rules from 6b are written as tests.
- Write **3 targets**, each linked to an existing Blue shift's company so both sides share a world.
- **Done when:** the system test builds and launches a campaign, and the simulator and balance tests pass.

### M8 — Progression: XP, levels, streaks, badges
- XpEvent (with `side`) on scored completion; update that side's XP and level and `xp_total` in one transaction.
- Onboarding: "Which side do you want to try first?" Then a side switcher on the dashboard.
- Streak logic with tests across day boundaries.
- Badges: First Catch, Eagle Eye (all flags, no hints), Clean Shift (3 stars), Productive Paranoid (all tasks done + all phish reported), Near Miss Ninja (close 3 bait pages before submitting), 7-Day Streak, **Red:** Fooled Carol, Budget Hacker (3 stars with half the budget left), **Both:** Purple Belt (3 stars on a shift and on its matching target).
- Awarded by a Solid Queue job, with a Turbo Stream toast.
- **Done when:** every badge rule is unit-tested.

### M9 — Leaderboards, profiles & polish
- Leaderboards with tabs for **Blue / Red / Overall**, weekly (sum of XpEvents this ISO week, filtered by side) and all-time. Cached 60s, with the current user's rank always shown. Ties are broken by who reached the score first.
- Public profile `/u/:display_name` showing Red and Blue levels side by side, a "preferred side" tag, and badges.
- Dashboard: continue shift, streak, suggested next shift.
- Accessibility: keyboard-only play, ARIA, WCAG AA contrast, visible focus. Onboarding tutorial shift.
- Expand content to **~15 shifts across 3 tracks** (≈70 messages).
- **Done when:** axe passes and Lighthouse ≥ 90 on key pages.

### M10 — Production deploy
- Kamal 2, managed Postgres or an accessory, SSL via kamal-proxy, daily backups, production mailer, error tracking, uptime check.
- Run `content:import` on deploy. Privacy and terms pages (placeholders flagged for review).
- **Done when:** the app is live, sign-up email arrives, and a full shift works in production.

## 8. Content YAML example

```yaml
# content/tracks/phishing-basics/month-end-at-larkhill.yml
slug: month-end-at-larkhill
title: "Month-end at Larkhill Finance"
kind: inbox
difficulty: beginner
time_budget_minutes: 30
position: 2
briefing: >
  It's month-end. You need to approve a supplier payment and sign your new
  HR policy before 5pm. Red has been studying your team on social media...
learning_summary: >
  Attackers copy the tasks you're already expecting. Check where a link really
  goes, and verify payment changes through a known channel.

tasks:
  - { key: pay_supplier, title: "Approve Tidemark invoice #4471", due_at_minute: 20, points: 40 }
  - { key: sign_policy, title: "Sign the updated HR policy", due_at_minute: 30, points: 30 }

messages:
  - key: real_invoice
    channel: email
    arrives_at_minute: 0
    legit: true
    from_name: "Tidemark Supply"
    from_address: "accounts@tidemark.example"
    to_address: "you@larkhill.example"
    subject: "Invoice #4471 ready for approval"
    body_html: |
      <p>Hi, invoice #4471 is ready in the supplier portal.</p>
      <p><a href="https://portal.larkhill.example/invoices/4471">Review invoice</a></p>
    links:
      - { match: "portal.larkhill.example", outcome: completes_task, task: pay_supplier, landing: portal_task }

  - key: fake_invoice
    channel: email
    arrives_at_minute: 3
    legit: false
    techniques: [lookalike_domain, urgency_pretext, credential_harvest]
    from_name: "Tidemark Supply"
    from_address: "accounts@tidemark-billing.example"
    reply_to: "nw.payments@freemail.test"
    to_address: "you@larkhill.example"
    subject: "URGENT: Invoice #4471 — updated bank details"
    body_html: |
      <p>Our bank details have changed. Payment must be approved within 1 hour.</p>
      <p><a href="https://larkhill-portal.example.net/login">https://portal.larkhill.example/invoices/4471</a></p>
    links:
      - { match: "larkhill-portal.example.net", outcome: bait_landing, landing: credential_harvest }
    verify_result: "Tidemark's finance team: 'We haven't changed our bank details.'"
    red_flags:   # anchors use the neutral ids the importer assigns: p1, p2, l1, from, reply_to, subject
      - { key: lookalike, anchor: from, points: 10, label: "Lookalike sender domain",
          explanation: "tidemark-billing.example is not tidemark.example." }
      - { key: bank_change, anchor: p1, points: 10, label: "Changed bank details + urgency",
          explanation: "A classic payment-fraud pretext. Always verify by phone." }
      - { key: link_mismatch, anchor: l1, points: 10, label: "Link text ≠ destination",
          explanation: "The text shows the real portal, but the link goes to larkhill-portal.example.net." }

  - key: hr_policy
    channel: email
    arrives_at_minute: 5
    legit: true
    from_name: "Larkhill HR"
    from_address: "hr@larkhill.example"
    to_address: "you@larkhill.example"
    subject: "Action needed: sign the updated policy"
    body_html: |
      <p>Please sign the updated hybrid working policy by end of day.</p>
      <p><a href="https://hr.larkhill.example/sign/2291">Open policy</a></p>
    links:
      - { match: "hr.larkhill.example", outcome: completes_task, task: sign_policy, landing: portal_task }

hints:
  - { body: "Two emails mention the same invoice. Compare the sender domains closely.", penalty_percent: 20 }
```

## 9. Definition of done for the MVP

- All milestones complete with green CI (tests, rubocop, brakeman, bundler-audit)
- ~15 Blue shifts across 3 tracks, 3+ Red Workshop targets, 3 bot personas, 9 badges, ≈12 techniques
- A new player can choose either side, play it, switch sides, and see separate Red and Blue progress
- System tests verify that no hidden answers (`legit`, outcomes, task mappings, techniques) appear in any HTML or Turbo Stream before the debrief
- Deployed with backups, error tracking and working email
- README covers setup, content authoring and deployment

## 10. Design decisions to keep the Red side open

- `Shift.author_type` (system/player) and `author_side` are already in the schema. A future player-built Red campaign is just a Shift with `author_type: player`.
- `Technique` is the shared vocabulary. Red's future "attack cards" are Techniques plus message templates, and Blue's future "controls" will counter specific Techniques.
- `AttemptAction` is a full event log, so async multiplayer (Red submits a campaign, Blue plays it later) and the debrief replay reuse it unchanged.
- A `RedCampaign` renders to the same fields as a `Message`, so a submitted campaign can later be dropped into a Blue shift as a real player's attack, without any conversion step.
- Bot personas are the AI opponent for both sides: they judge Red now and can later stand in for a missing Blue player in multiplayer.

## 11. After the MVP (don't build yet)

1. **Developing Red's Workshop** (in roughly this order):
   - **Multi-email campaigns:** a sequence of messages (warm-up email, then the bait), which teaches pretexting and building trust.
   - **Recon phase as gameplay:** spend budget on "OSINT" actions (fictional staff profiles, the company website) to unlock high-relevance cards.
   - **Limited customisation:** choose between several pre-written variants per card. If free text is ever added, it must go through moderation and reserved-domain checks, and it's only shown to other players after review.
   - **Bot learning:** bots get better at techniques that are used a lot, so Red has to keep varying tactics ("meta" shifts each season).
   - **More attack types:** smishing, vishing scripts (choose-your-path phone calls), and fake IT support chat.
2. **Async multiplayer duels:** Red's submitted campaign is inserted into a human Blue's shift; results go back to Red as a debrief. An AI bot fills whichever side has no player. Separate Red and Blue Glicko-2 ratings.
3. **Defence vs Campaign:** Blue spends a budget on controls (SPF/DKIM/DMARC, link rewriting, attachment sandbox, MFA, training) that block or weaken specific Techniques before Red attacks.
4. **Kill chain board** (MITRE ATT&CK stages), **simulated company** with NPC staff, **seasons** where everyone swaps sides.
5. Organisations and teams, billing (Pay + Stripe), admin content editor.
6. **Live real-time battles and live labs** as a separate isolated service (Phoenix is the likely choice).
