# Phase 1 MVP Plan — Red vs Blue Cyber Training Game

> Hand this file to Claude Code. Work through the milestones **in order**. Finish each one (code + tests + green CI) before starting the next. Ask before deviating from the stack or the conventions below.

## 1. Product summary

A gamified web app built around a **Red team vs Blue team** premise. Red (the attacker) crafts social-engineering attacks; Blue (the defender) has to catch them while still getting their job done. Every round ends with a **Purple debrief** that replays both sides' moves.

**Players can play on either side and find out which they prefer.** Each side has its own XP, level and leaderboard.
- **Blue (main MVP mode):** play **shifts**. A shift is one round: a simulated working day spent clearing an inbox, where every genuine message needs dealing with properly and the phishing needs reporting. The attacks in it are hand-authored scenarios, presented as "Red's campaign".
- **Red (simple MVP mode): "Red's Workshop."** Build a phishing email from technique cards on a budget, aimed at a shift's fictional company. A panel of simulated Blue bots then judges it. There's no human opponent yet.

Multiplayer, where Red's campaigns are played by real Blues, comes later (section 11). The data model is built for it now.

### The core mechanic: a working day, not a quiz

> **Redesigned in M6b.** The task list, minute clock and live meters described below were built in
> M3–M6 and are replaced by M6b ("The inbox is the job"): the inbox is the job, genuine messages carry
> hidden expectations, time is real time with a speed bonus, and nothing during the shift says whether
> you were right. Where this section and M6b disagree, M6b wins.

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
- **The server is the single source of truth.** Every game action (open message, expand headers, verify, click link, submit credentials, reply, report, flag, archive, clock off) is a POST that the server records with its own timestamp. The client never computes the score, the time or the outcome, and never sends a time.
- **Never send hidden answers to the browser:** no `legit` flags, expectations, red-flag lists or quotes, link outcomes or technique tags before the debrief.
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
8. **Anti-cheat:** a shift attempt is created server-side with a random token. Actions must reference an open attempt owned by the current user. Each user gets XP only for their first completed attempt per shift. Time is measured server-side, and actions on a finished or expired attempt are rejected.
9. Brakeman and bundler-audit must pass in CI.

## 5. Data model

> **M6b changes:** `Task` and `due_at_minute` go; `Shift` swaps `time_budget_minutes` for
> `par_minutes`; `Message` swaps `arrives_at_minute` for an arrival trigger (`start`,
> `after_handled`, `after`) and gains `expects`, `urgent_within` and `answer_in_key`/`answer_in_quote`;
> `RedFlag` gains `quote` and `contradicts_key`/`contradicts_quote`;
> `ShiftAttempt` gains `relaxed` and status `clocked_off`/`expired`, and loses `clock_minutes`;
> `AttemptAction` loses `minute`/`cost_minutes` in favour of its timestamp, gains `archive`,
> `send_reply` and `clock_off`, and loses `complete_task`; `User` gains `relaxed_mode`. The model
> below is as built in M3–M6.

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

> **Superseded by M6b ("The inbox is the job").** This section describes the engine as built in
> M3–M6: a task list, a minute clock driven by action costs, and live meters. M6b replaces the tasks,
> the clock and the meters, and changes the scoring. Where the two disagree, M6b wins.

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

### M6b — The inbox is the job
A redesign of Blue's shift after playtesting. The old engine leaked answers: the task list told you
when you were done, and ticking a task off revealed which look-alike message was the fake. "Wait for
new mail (N min)" told you exactly when the next message would land, and the live meters and
compromise alert told you mid-shift that you'd got something wrong. Genuine messages without a task
link scored nothing however you handled them. M6b replaces the task list, the minute clock, the
meters and the wait button.

**Ending a shift**
- A shift is a fixed set of messages, and it **ends when every one has been dealt with**. The player
  goes straight to the debrief.
- There's no task list, no wait button and no "End shift" button. A **Clock off early** button ends the
  shift early (status `clocked_off`, move `clock_off`), and anything left counts as ignored. Clocking off
  never earns the speed bonus.
- The inbox shows only what's in it, never a total, so the player can't tell whether more is coming.

**Dealing with a message.** Each message ends in one of three states:
- **Reported**: the player thinks it's a phish.
- **Done**: they replied, or acted through its link, then archived it.
- **Archived**: nothing was needed.

Flags are notes made along the way. They don't finish a message.

**How messages arrive.** Authored per message:
- `arrives: start`: in the inbox when the shift begins.
- `after_handled: 2`: arrives once any 2 messages have been dealt with.
- `after: courier_slot`: a follow-up, arriving once that message has been dealt with.

The rules:
- Triggers depend only on *that* a message was dealt with, never on whether it was handled right.
  For example, there's no "thanks for reporting" from security after a correct report.
- No branching for now: a message always triggers the same follow-up, whichever reply was sent.
- The importer checks that every message can arrive and that no triggers loop.
- **A fake never arrives after the genuine message it imitates.** A phish with `imitates: <key>`
  arrives at the start, or on exactly the same trigger as that genuine message (and is then placed
  above it). Otherwise the player could act on the real one first and spot the fake as a duplicate,
  instead of having to decide between them. The importer checks this.
- **Phishes get follow-ups too.** If any genuine message has an `after:` follow-up, at least one phish
  must have one as well (the attacker chasing: "Did you get my invoice?"). Otherwise "something arrived
  after I reported that" would mean it was genuine. The importer checks this.
- The starting inbox order is shuffled per attempt, seeded from the attempt token.

**What each message expects** (hidden on the server, like `legit`):
- Each genuine message has `expects: reply | act | archive`. A phish expects a report.
- `act` means doing the thing through the message's link, on a portal page.
- `reply` means sending any of its canned replies whose outcome is `safe`. Replies gain a fourth
  outcome, `poor` (an unhelpful or rude answer to a genuine message): the message counts as dealt
  with, but scores like archiving it without doing what was needed.
- A genuine message can be urgent: `urgent_within: 10` means deal with it within 10 minutes of its
  arrival.

**Scoring** (all of it revealed only in the debrief):

| The player did this | To a genuine message | To a phish |
|---|---|---|
| Handled it as expected | `+points`, half if an urgent one was late | +30 for reporting |
| Archived it without doing what was needed, or sent a poor reply | `−points / 2` | 0 |
| Left it unhandled when the shift ended (clocked off, or expired) | `−points / 2`, or 0 if it expected archiving | 0 |
| Reported it | −15 | |
| Fell for it (signed in, ran a file, handed over a code) | | −50 |
| Clicked a bait link but backed out (near miss) | | −10 |

Red flags and hints score as before: +each flag's points, −10 per wrong flag, and each hint costs its
`penalty_percent` of the maximum. Total = message points + flags + speed bonus − hints, floored at 0.
Stars are 1–3 by thresholds of the maximum, and 3 stars needs no compromise.

**Lazy play must never pay.** The scorecard tests, and the importer for every shift, play these
strategies and require each to score **below 1 star** and below a careful player:
- report everything;
- archive everything;
- clock off at once;
- flag every sentence of every message, then report everything.

The importer rejects a shift where any of them reaches 1 star, so content can't drift into an
exploit.

**Time**
- Time is real time, measured on the server from the start of the attempt. **No clock is shown.**
- **Calling the sender back** is instant but adds a **30 s time penalty** to the attempt's elapsed
  time. Every other move is free.
- **Speed bonus:** each shift has a target time (`par_minutes`). Only a **cleared inbox** earns it
  (never clocking off or expiry). The player gets +20 for each full 5-minute block under par, times
  the share of messages handled as expected (phishes reported, genuine messages as they expected), so
  rushing through and getting things wrong earns little. Nothing over par, and no per-second scoring.
- An attempt left open for 2 hours closes the next time it's visited, and anything unhandled counts
  as ignored.
- Elapsed time and penalties are computed only on the server. The browser never sends a time.

**Relaxed mode** (a site-wide account setting, on the account page): no speed bonus and no urgency
penalties. It's copied onto the attempt when it starts (`shift_attempts.relaxed`), so changing the
setting mid-shift does nothing. Relaxed and timed scores are kept separately for the M9 leaderboards,
which count each player's **first** scored attempt per shift only: a replay is faster because the
player already knows the answers. This is also the accessible option for
anyone who doesn't want to be timed (WCAG 2.2.1).

**No clues during the shift**
- No productivity or security meters, and no compromise alert. The debrief says what happened ("4
  minutes in, someone signed in as you from abroad").
- After the player signs in on a bait page, it quietly sends them on to a plausible page, as real
  phishing kits do.
- Real portals end on the same kind of plain "Submitted" confirmation, so neither page says whether
  the player was right.

**Fine-grained flags**
- In flag mode the player can **highlight any words** by dragging across them, such as "within 12
  hours" or "Dear valued customer".
- **Clicking without dragging flags the whole sentence.** Sentences are reachable by Tab and Enter, so
  this is also the keyboard and touch route.
- Headers (sender, To, Reply-To, subject) stay as whole parts. Clicking a highlight removes it.
- **Red flags are authored as quoted phrases:** `{ quote: "within 12 hours", in: p1, points, label,
  explanation }`. The importer checks the quote appears exactly once in that paragraph. Header red
  flags keep `anchor: from` and so on.
- **The importer splits every paragraph into sentences with neutral ids** (`p1s1`, `p1s2`…). Every
  sentence gets one, so the markup says nothing about where the red flags are.
- The browser posts only the paragraph and the character range of the selection. The quote never
  reaches the page.
- **Both sides count characters the same way:** a paragraph's text is its text nodes in document
  order, with each run of whitespace collapsed to one space and the ends trimmed. The importer works
  this out and stores it, the browser applies the same rule to the element's `textContent`, and the
  server rejects ranges outside it.
- A quote must sit inside one sentence; the importer rejects quotes that cross a sentence boundary.
- **What counts as a hit:**
  - A highlight finds a red flag if it covers **at least 60%** of the quote's characters and is **no
    longer than twice the quote, or the quote plus 20 characters**, whichever is longer. Highlighting
    a whole paragraph to catch everything doesn't count.
  - A sentence click finds **every** red flag whose quote is in that sentence.
  - Each red flag scores once, however many flags found it. A flag that finds nothing, including a
    highlight that overlaps a quote but is too long, is a wrong flag (−10).
- **The debrief shows each message with the player's highlights and the real red flags marked on
  the text:** caught, missed, and flagged by mistake.

**Read it, you'll need it later.** Inspired by mystery games like KC7: a shift should be a small story
in which facts arrive early and pay off later, so the player has to actually read every message rather
than judge each one alone. Two authored links between messages, both secret until the debrief:
- **A red flag can contradict an earlier message.** `contradicts: { message: it_welcome, quote: "We'll
  never email you about your password" }` on a phish's red flag says *which genuine message gave the game
  away*. IT says it never emails about passwords, then a "password expiry" email arrives; Finance says
  Tidemark's invoices only come through the portal, then one arrives as an attachment. The flag itself is
  still a quote or anchor in the phish. The debrief shows the two side by side: "Earlier, Larkhill IT told
  you: “…”".
- **Questions come as replies.** Instead of a debrief quiz, colleagues *ask* things in the course of the
  job, and the right answer is in an earlier message. Alex asks which room your induction is in (HR's email
  said); the courier asks for the delivery reference (it was in the booking). `answer_in: { message:
  hr_onboarding, quote: "Room 4B" }` on the asking message names where the answer was; its canned replies
  offer the right answer (`safe`) and plausible wrong ones (`poor`), so a wrong answer scores like a poor
  reply. The debrief says where the answer was: "It was in HR's email: “…”".

The importer checks:
- The referenced message is another message in the shift, and the quote appears in its text exactly once.
- A `contradicts` source is genuine (the truth comes from the real company, never from a phish).
- The source is **always in the inbox before the message that relies on it**: it arrives at the start, or
  the dependent message arrives `after:` it (directly, or through a chain of `after:` triggers). Otherwise
  the player could meet the question before the answer.
- A message with `answer_in` is genuine, expects a reply, and offers at least one `poor` (wrong) answer.
- `answer_in` may point at a **phish** only if the asking message arrives last (`after_handled:` every other
  message), when every decision has been made. This is how an end-of-shift "security team" email can ask
  "which supplier did they pretend to be?" without giving anything away mid-shift.

Neither link reaches the browser: the source message is ordinary content, and the link between them, like
`legit`, is an answer. Every re-authored shift sets up at least one fact that a later message
contradicts, and at least one question answered by an earlier message.

**What goes**
- The `tasks` table and `due_at_minute`.
- Per-move minute costs (`action_costs`) and the minute clock.
- The productivity and security meters, and the wait button.

What stays: the action log, opaque message refs, the in-game browser, canned replies, hints, the
Purple debrief, XP only for the first scored attempt, and `imitates` (now in terms of triggers).

**Also update** `CLAUDE.md` (the game moves, and "actions after the clock runs out" becomes "actions on
a closed or expired attempt"), the README, and the "Productive Paranoid" badge, which becomes "handle
every genuine message as it needed and report every phish in a single shift".

**Content.** Re-author all four shifts for this model. Each gets:
- genuine messages that need a reply (like Sam's text) or an action;
- at least one triggered follow-up;
- a genuine message that looks suspicious;
- red flags as quoted phrases;
- a fact set up early that a later phish contradicts (`contradicts:`), and a question answered by an earlier
  message (`answer_in:`).

**Done when:**
- System tests cover clearing an inbox that has a triggered follow-up, clocking off early, relaxed
  mode against timed mode, the 30 s call penalty, and flagging by highlight and by sentence. They also check that no
  score, outcome, red-flag quote or expectation reaches the page mid-shift.
- The scorecard, the trigger rules (including imitation order and phish follow-ups), the
  highlight-matching rules and the lazy-play strategies are unit-tested.
- The `contradicts` and `answer_in` import rules are unit-tested, and a system test answers a colleague's
  question wrongly and sees the debrief point back to the earlier message.

### M7 — Red's Workshop
- Models from section 5 (Target, TargetOption, BotPersona, RedCampaign). Seed 3 bot personas. Extend the importer for `content/targets/*.yml`.
- Workshop flow: target list → recon brief → card builder (slots, budget bar, live email preview via Turbo Frame) → launch → animated bot results → Purple debrief.
- `RedCampaign::Simulation` is a pure, seeded, fully unit-tested class, and the balance rules from 6b are written as tests.
- Write **3 targets**, each linked to an existing Blue shift's company so both sides share a world.
- **Done when:** the system test builds and launches a campaign, and the simulator and balance tests pass.

### M7b — Who are you? Personas and private details
So far a phish only gets you if you click or press. This milestone lets the player **hand something
over**. Each attempt gives the player a persona with private details, and genuine jobs need some of them,
so refusing everything doesn't work either. The lesson becomes "who's asking, through which channel, and
do they need this?" rather than "never share".

**The persona card**
- When the shift starts, the player gets a welcome pack: name and role (fixed per shift), plus details
  generated **for each attempt**: staff number, desk extension, a memorable word for the IT phone line,
  and a "security question" answer. Values are generated on the server, seeded from the attempt token
  like `message_ref`, so answers can't be shared between players and a replay can't be done from memory.
- Values are obviously fictional and realistic in kind: "Memorable word: TANGERINE OTTER", "Staff number:
  LH-48213". The generators use their own fictional word lists; the importer checks every one.
- The card stays open in a side panel (keyboard and screen-reader reachable, and on the phone layout too).
  Looking things up is part of the job.
- **The MFA code is live:** a code appears on the in-game phone when a real sign-in happens (using a
  portal that asks for it), and a phish may ask for it moments later.

**Details learned from messages.** Not everything is on the card. Earlier messages can tell the player
things they'll need later, or must keep to themselves: the manager's codeword for approving payments,
the time the CEO's flight leaves, the room the board meets in, the name of a new supplier.
- Authored as a quote in the message, like a red flag:
  `details: [{ key: wire_codeword, quote: "BLUEBELL", sensitivity: secret }]`. A detail's value can be
  fixed, or generated for each attempt (`value: word`), and is substituted into the body.
- The player **saves a note** by highlighting words in a message (the same highlight as flagging, in a
  "save to notes" mode). The note becomes a chip with the words as its label. The server matches the
  highlight against the authored details with the red-flag coverage rules, privately: a note that matches
  nothing is just a note, and the page never says whether a note "counts".
- The importer checks a detail is in the inbox before any message that needs or wants it (as with
  `answer_in`).
- This builds on M6b's `answer_in`: a question can be answered by sharing a saved note, as well as by
  picking a canned reply.

**Sharing: chips, never typing**
- A message that asks for details offers a **Send details** composer alongside its canned replies: pick
  chips from the card and from saved notes, then send. Portal and bait pages have labelled fields, each
  filled by picking a chip.
- No free-text field anywhere, so nobody can type a real password into the game. Rule 5 holds: the
  server records which chips were shared with which message, never anything typed.
- New move: `share_details` (an `AttemptAction` with the detail keys and the message or page), and
  `save_note`. Both are resources with a one-line `create`, like the other moves.

**Sensitivity and scoring** (hidden until the debrief, like `legit`):

| Sensitivity | Examples | Who may have it |
|---|---|---|
| `public` | Name, role, desk | Anyone: it's on the intranet |
| `internal` | Staff number, extension, supplier name | Genuine colleagues and systems that need it |
| `secret` | Memorable word, codeword, travel times | Only the one genuine place that asks, through the right channel |
| `never` | Password, MFA code | Nobody, ever |

- Genuine messages declare what they `need:`; phishes declare what they `want:`. Both stay on the server.
- **To a genuine message:** sharing everything it needs means done. Sharing nothing, or refusing, means
  not done, as now. Sharing details it didn't need is **oversharing**: −5 per `internal`, −15 per `secret`.
  Sharing a `never` detail with anyone is a compromise.
- **To a phish:** sharing anything above `public` is falling for it, costing −20 per `internal`, −50 per
  `secret` or `never` detail (capped at the compromise cost per message), and stars need no compromise.
- **Lazy play** gains two strategies that must stay below one star: **share nothing** (genuine jobs
  aren't done) and **share everything with everyone** (every phish is a compromise).

**The debrief: "What Red now knows."** A panel listing every detail the player gave a phish, and what
Red could do with it: "You gave away your staff number and memorable word. With those, Red could call
the IT service desk as you and reset your password." Each genuine message says whether it got what it
needed, and what was overshared.

**Never sent to the browser:** what a message needs or wants, sensitivities, which notes match a detail,
or which details exist in a message. The persona's own values are the player's and are shown.

**Content.** Re-author the shifts so each has:
- a genuine message that needs a card detail (HR's form needs your staff number);
- a phish that wants a card detail (the "IT" chat wants your memorable word or MFA code);
- a detail learned from a message that's needed later by a genuine message, and wanted by a phish
  (Priya tells you the payment codeword; Finance needs it; a fake "Priya" asks you to confirm it).

**Also update** CLAUDE.md (the new moves, and the secrets list), the README's content guide, and
`RedCampaign` cards: a Red "ask for details" card targets a sensitivity level, and bots fall for it
according to their persona.

**Done when:**
- Unit tests cover persona generation (stable per attempt, different between attempts), note matching,
  sharing and its scoring, the new lazy-play strategies and the importer rules.
- System tests: start a shift and read the card; save a note from a message and share it with the
  genuine message that needs it; give a detail to a phish and see it in "What Red now knows"; and check
  that no needs, wants, sensitivities or note matches reach the page mid-shift.

### M8 — Progression: XP, levels, streaks, badges
- XpEvent (with `side`) on scored completion; update that side's XP and level and `xp_total` in one transaction.
- Onboarding: "Which side do you want to try first?" Then a side switcher on the dashboard.
- Streak logic with tests across day boundaries.
- Badges: First Catch, Eagle Eye (all flags, no hints), Clean Shift (3 stars), Productive Paranoid (every genuine message handled as it needed + every phish reported), Near Miss Ninja (close 3 bait pages before submitting), 7-Day Streak, **Red:** Fooled Carol, Budget Hacker (3 stars with half the budget left), **Both:** Purple Belt (3 stars on a shift and on its matching target).
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

> This is the M3–M6 format. M6b replaces `tasks`, `arrives_at_minute` and anchor-only red flags with
> arrival triggers, `expects` and quoted red flags; the re-authored shifts in `content/` are the
> reference once M6b lands.

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
- System tests verify that no hidden answers (`legit`, outcomes, expectations, red-flag quotes, techniques) appear in any HTML or Turbo Stream before the debrief
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
4. **A story across each track, a mystery to solve** (building on M6b's `contradicts` and `answer_in`):
   - **One attacker per track.** The same invented group returns shift after shift: a lookalike domain
     reused, a lure improved, a detail lifted from an earlier phish. Shift 3's phish uses a fact that
     shift 1's phish was fishing for, which teaches that attackers do recon (and sets up Red's recon phase).
   - **Facts carry across shifts.** `answer_in` and `contradicts` can name a message in an earlier shift of
     the same track; the track page keeps past shifts' genuine messages readable as the player's "mail
     archive". The importer checks the earlier shift comes first in the track.
   - **The investigation comes as mail, not a quiz.** The last shift of a track ends with emails from
     Larkhill's security team asking what the player saw ("Which supplier did they pretend to be?",
     "Which domain turned up in all three attacks?"), answered by reply, scored like any reply and
     explained in the debrief. These arrive only once every other decision is made.
   - **Briefings move the story on, the same for everyone** ("after last week's invoice scare, Finance now
     calls every new supplier back"). The story never branches on how the player did: that would hint at
     their mistakes and break the "triggers never depend on being right" rule.
   - **Leaked details used against you (parked).** Once M7b lets players give details away, a later
     phish could use what they leaked ("Hi, staff #48213…") to look more convincing, as real attackers do.
     Within a shift this would break "content never depends on being right": a sharp player could work
     out that the earlier message was a phish. Across shifts it fits the one-attacker arc, but it makes the
     story branch on how the player did. Revisit once the arc exists.
   - Smaller ideas from KC7: a recurring narrator for the Purple debrief, guest play without saved
     progress (for classrooms), and educator-hosted competitions (with item 6).
5. **Kill chain board** (MITRE ATT&CK stages), **simulated company** with NPC staff, **seasons** where everyone swaps sides.
6. Organisations and teams, billing (Pay + Stripe), admin content editor.
7. **Live real-time battles and live labs** as a separate isolated service (Phoenix is the likely choice).
