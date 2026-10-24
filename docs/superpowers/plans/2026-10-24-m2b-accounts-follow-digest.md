# M2b: Accounts, Following and the Daily Email — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A visitor can create an account by emailed link, add a passkey, follow bills and reps, and get one email a day only when something they follow changed. With that, M2's "done when" is met: a user can find their reps and follow a bill end to end.

**Architecture:** Accounts come from `mix phx.gen.auth` (Phoenix 1.8, magic-link flow) with passwords removed. Passkeys follow turley.dev (`wax_`, a `user_keys` table, `PasskeyLogin`/`PasskeyRegister` LiveView hooks). Follows are one domain table. The digest is an Oban cron at 07:00 America/New_York that enqueues one unique job per user and per day. Each job collects rows first stored since that user's last digest and sends through Swoosh: Resend in production, the local mailbox in dev.

**Tech Stack:** Phoenix 1.8 / LiveView, Ecto, Oban, Swoosh (+ `Swoosh.Adapters.Resend`), `wax_ ~> 0.7.0`.

**Spec:** `docs/superpowers/specs/2026-10-23-m2-frontend-design.md` (sections Accounts, Follow and the daily email, This week, Settled 4–6), plus the reference implementation at `~/Projects/turley.dev`.

## Global Constraints

- No UI or domain code may know it is federal (`test/the_floor/boundary_test.exs`); UI copy names no legislature.
- No passwords. Sign in by emailed link or passkey. Finding reps, rep pages, bill pages and This week all work without an account; only following needs one.
- Privacy: addresses and ZIP codes are never stored, logged or put in a URL; an account stores only the district key. `filter_parameters` keeps `address`, `street` and `zip`.
- Passkeys: rp_id `everydaycitizen.vote`, origin `https://everydaycitizen.vote` in production; `localhost` / `http://localhost:4000` in dev; `http://localhost:4002` in test. **The rp_id can never change once passkeys exist.**
- Email: from `Everyday Citizen <hello@everydaycitizen.vote>`. Each digest item links to its page; every email carries one-click unsubscribe (link plus `List-Unsubscribe` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click` headers).
- Digest: "changed" means a row whose `inserted_at` is after the user's `digest_sent_at`, never a re-fetch. Day = America/New_York, sent at 07:00. A missed day catches up. At most one digest per user per day.
- Secrets come from env vars in `config/runtime.exs`, each documented in `.env.example`: `RESEND_API_KEY`.
- Client JS only as LiveView hooks.
- Product voice: the email and pages describe events ("New action", "Roll-call vote"), never why.

## Review Focus

1. A magic link or passkey sign-in while a district is in the session: the account takes that district when it has none; an account's saved district is used when the session has none; entering a new address while signed in replaces the account's district.
2. Re-fetching an unchanged bill (actions upserted, vote positions deleted and re-inserted) must not put it in the next digest; only rows first stored since `digest_sent_at` count, and votes key on `votes.inserted_at`, not positions.
3. The digest job retried, run twice the same day or run after downtime: never two emails the same day, never a lost day (`digest_sent_at` moves only after a successful send, to the run's cutoff time, not "now").
4. Unsubscribe link: works without signing in, is not guessable, and an old link cannot re-enable anything. Following something while unsubscribed says that digests are off.
5. Passkey payloads that are garbled or hostile never crash the LiveView and never reveal whether a passkey exists (every failure is the same message).

## Owner steps (outside the code; needed before production sign-in works)

1. Create a Resend account and add the domain `everydaycitizen.vote`.
2. At Namecheap, add the DNS records Resend shows (SPF/DKIM TXT and the MX for the bounce subdomain); wait for Resend to say Verified.
3. Create an API key with sending access and set it: `fly secrets set RESEND_API_KEY=... -a thefloor-vote`.

Until step 3 is done, the merge waits: Task 6 makes production boot require `RESEND_API_KEY`, so a deploy without it fails rather than silently dropping sign-in emails.

---

### Task 1: Deploys don't strand running jobs

**Files:** Create `lib/the_floor/oban_rescue.ex`; Modify `lib/the_floor/application.ex`; Test `test/the_floor/oban_rescue_test.exs`

**Interfaces:**
- Produces: `TheFloor.ObanRescue.rescue_orphans(node :: String.t()) :: non_neg_integer()`. It sets `state: "available"` on jobs `executing` whose `attempted_by` names a different node, and returns the count. It runs once at startup, from a `Task` placed after Oban in the supervision tree (not in test).

- [ ] Step 1 (test first): three jobs, executing on `"old@1"`, executing on `"me@1"` and available. `rescue_orphans("me@1")` returns 1 and only the first becomes available.
- [ ] Step 2: run it; it fails because the module is undefined.
- [ ] Step 3: implement it. `attempted_by` is `[node | _]`; compare its first element. Check in a release that `Node.self()` changes per deploy (`RELEASE_NODE` includes the image ref); if it does not, add `rel/env.sh.eex` setting `RELEASE_NODE="the_floor-${FLY_IMAGE_REF##*:}@${FLY_PRIVATE_IP}"`.
- [ ] Step 4: `mix test` passes. Commit `fix: release jobs a previous deploy left executing`.

### Task 2: Link each bill to its official page for people

The "Source record" link on API-updated bills points at `api.congress.gov`, which is useless to a person (a deferred ruling from M2a).

**Files:** migration `add :web_url, :string` on `bills`; `lib/the_floor/legislation/bill.ex`, `lib/the_floor/ingest/records.ex` (`Bill.web_url`), the writer, the federal normalizers that build `Records.Bill` (API and bulk), `lib/the_floor/adapters/federal/jobs/` new on-demand `BackfillBillWebUrls` (`bill_web_urls` in `Jobs.on_demand/0`), `lib/the_floor_web/live/bill_live.ex`.

**Interfaces:**
- Produces: `bills.web_url`, set by the adapter. The federal value is `https://www.congress.gov/bill/{congress}th-congress/{type-slug}/{number}` (`hr` → `house-bill`, `s` → `senate-bill`, `hres` → `house-resolution`, `sres` → `senate-resolution`, `hjres` → `house-joint-resolution`, `sjres` → `senate-joint-resolution`, `hconres` → `house-concurrent-resolution`, `sconres` → `senate-concurrent-resolution`; ordinal suffix rules: 1st/2nd/3rd/…/11th–13th/21st…).
- The bill page link reads "Official page" and points at `web_url || source.url`.

- [ ] Tests first: the normalizer test asserts S. 5 → `https://www.congress.gov/bill/119th-congress/senate-bill/5` and H.Con.Res. 3 → `.../house-concurrent-resolution/3`; the backfill job fills nulls only; the bill page links `web_url` when present. Watch them fail; implement; `mix test` passes; commit `feat: link bills to their official page`.

### Task 3: Accounts by emailed link

**Files:** generated by `mix phx.gen.auth Accounts User users --live` (accept the magic-link default), then trimmed. Modify `lib/the_floor_web/router.ex`, `lib/the_floor_web/components/layouts.ex` (header gains "Sign in" or "Account"), `lib/the_floor_web/controllers/district_controller.ex`.

**Interfaces:**
- Produces: `TheFloor.Accounts` (generated API), `TheFloor.Accounts.User` with `email`, `district :string`, `digest_enabled :boolean default true`, `digest_sent_at :utc_datetime`; `TheFloor.Accounts.Scope`; `TheFloorWeb.UserAuth` with `on_mount :mount_current_scope` on every live session and `:require_authenticated` for account pages; `Accounts.put_district(user, key) :: {:ok, User.t()}`.
- Removes: password fields, password login, password settings (the generator's optional password path). `hashed_password` stays out of the schema.

- [ ] Tests first (beyond the generated ones, which must pass after trimming):
  - Signing in by link while the session holds `IA-1` and the account has no district saves `IA-1` on the account.
  - Signing in with an account district `IA-1` and none in the session puts `IA-1` in the session.
  - Signed in, a ZIP lookup that lands on `IA-2` updates the account to `IA-2`.
  - No password field appears on the login or settings pages.
  - The magic-link email body contains no address or ZIP.
- [ ] Implement; `mix test` passes; commit `feat: accounts by emailed link`.

### Task 4: Passkeys

**Files:** add `{:wax_, "~> 0.7.0"}`; create `lib/the_floor/accounts/{passkeys,user_key,cose_key}.ex`, migration `user_keys` (as turley.dev: `credential_id` binary unique, `public_key` binary, `aaguid`, `sign_count`, `label`, `last_used_at`, `user_id` on delete cascade) and `users_tokens.user_key_id` (nullable, on delete cascade, so revoking a passkey ends its sessions); `assets/js/passkeys.js` (from turley.dev, renamed modules only) registered in `assets/js/app.js`; `test/support/fixtures/webauthn_fixtures.ex` (from turley.dev); config `:the_floor, :webauthn` in config/test/runtime as Global Constraints.

**Interfaces:**
- Consumes: `TheFloor.Accounts.User`, `Scope` (Task 3).
- Produces: `Passkeys.registration_options/1`, `register/4`, `authentication_options/0`, `authenticate/2`, `list_keys/1`, `revoke_key/2` with turley.dev's signatures and behavior (every failure is `{:error, :invalid_response}`); the login page's "Sign in with a passkey" button plus autofill; the account page's "Add a passkey" and per-key Remove.

- [ ] Tests first, using the software authenticator: register, then authenticate, gives the user; a replayed or garbled payload gives `{:error, :invalid_response}`; a backwards sign count is rejected; revoking a key deletes the sessions started with it; LiveView: the login page passkey flow signs in (hook events pushed directly), and the account page lists then removes a key.
- [ ] Implement by following turley.dev's `passkeys.ex`, `user_key.ex`, `cose_key.ex`, `passkeys.js` and `user_live/login.ex` passkey parts (no kid sign-in, pairing or admin). `mix test` passes. Commit `feat: passkeys`.

### Task 5: Follow bills and reps

**Files:** migration `follows` (`user_id` cascade, `bill_id` nullable cascade, `person_id` nullable cascade, check exactly one of the two set, unique `(user_id, bill_id)` and `(user_id, person_id)`, timestamps); create `lib/the_floor/follows.ex`, `lib/the_floor/follows/follow.ex`; modify `bill_live.ex` (title band button), `reps_live.ex` (button beside the rep's name), `this_week_live.ex` (third filter "Followed", signed-in only), account page (lists follows with Unfollow).

**Interfaces:**
- Produces: `Follows.follow(scope, {:bill, id} | {:person, id}) :: {:ok, Follow.t()}` (idempotent), `unfollow(scope, target) :: :ok`, `following?(scope, target) :: boolean`, `list(scope) :: [%{target, bill | person}]`, `followed_bill_ids(scope)`, `followed_person_ids(scope)`. `Calendar.week/3` gains `bills: ids` (events linking any of those bills).
- UI: signed out, the button is a link to sign in that returns to the page (`return_to`); signed in, it toggles "Follow" / "Following" with `aria-pressed`. When the user's digest is off, following shows "Daily email is off" with a link to turn it on.

- [ ] Tests first: follow twice gives one row; unfollow; the button signed out links to sign in with `return_to`; signed in, a click toggles and survives a reload; This week's Followed filter shows only events on followed bills; another user's follows are never visible.
- [ ] Implement; `mix test` passes; commit `feat: follow bills and reps`.

### Task 6: The daily email

**Files:** create `lib/the_floor/digest.ex` (collects items), `lib/the_floor/digest/email.ex` (Swoosh email, text and HTML), `lib/the_floor/jobs/digest_scheduler.ex` (cron `0 7 * * *`, America/New_York), `lib/the_floor/jobs/send_digest.ex` (queue `mail: 2`, `unique: [keys: [:user_id, :date], period: :infinity, states: :all]` scoped by args `%{"user_id", "date"}`); `lib/the_floor_web/controllers/unsubscribe_controller.ex` (`GET` shows a confirm button, `POST` unsubscribes; also accepts the RFC 8058 one-click `POST`); config: `runtime.exs` prod `TheFloor.Mailer, adapter: Swoosh.Adapters.Resend, api_key: RESEND_API_KEY` (raise if missing), `config :swoosh, api_client: Swoosh.ApiClient.Req` in prod; `.env.example` documents `RESEND_API_KEY`.

**Interfaces:**
- Consumes: `Follows.followed_bill_ids/1`, `followed_person_ids/1`, `User.digest_sent_at`, `digest_enabled`.
- Produces: `Digest.items(user, since :: DateTime.t(), until :: DateTime.t()) :: [%{kind, date, title, url, bill | person}]`, with these kinds:
  - followed bill: actions `inserted_at` in range; versions `inserted_at` in range; votes on the bill with `votes.inserted_at` in range;
  - followed rep: their votes (`votes.inserted_at`, with the person's position), sponsorships (`sponsorships.inserted_at`) and movement actions on their bills (as the feed).
  
  Deduplicated (a bill followed directly and through a rep appears once per item). `Digest.unsubscribe_token(user)` / `verify_unsubscribe(token)` use `Phoenix.Token` with salt `"digest unsubscribe"` and no max age.
- `SendDigest.perform`: cutoff = job's scheduled time. Items in `(digest_sent_at || user.inserted_at, cutoff]`. If none, it sets nothing and sends nothing. If some, it sends, then sets `digest_sent_at = cutoff`. A send error returns `{:error, _}` so Oban retries.

- [ ] Tests first: a re-fetched unchanged bill yields no items; a new action on a followed bill yields one item linking `/bills/<id>`; nothing changed means no email; two runs the same day give one email; a failed send leaves `digest_sent_at` alone; after a missed day, the next run covers both days; the email has `List-Unsubscribe` headers and an unsubscribe link; the unsubscribe POST turns digests off, and a tampered token is rejected; the digest never goes to a user with `digest_enabled: false`.
- [ ] Implement; `mix test` passes; commit `feat: daily email of what changed`.

### Task 7: Record and roll out

- [ ] Append DECISIONS: accounts (no passwords, district on account), passkeys (rp_id fixed forever), follows, digest semantics (`inserted_at`, cutoff, unique per day), startup job rescue, `bills.web_url`.
- [ ] Update CLAUDE.md's "Current milestone": M2 done when shipped.
- [ ] `mix precommit && mix credo --strict`.
- [ ] Final whole-branch review (fresh reviewer, most capable model).
- [ ] After the owner steps are done: merge, deploy, run `bill_web_urls`, then sign up on production with a real email, add a passkey, follow a bill and a rep, and confirm the next morning's digest (or trigger `SendDigest` for that user by hand).
