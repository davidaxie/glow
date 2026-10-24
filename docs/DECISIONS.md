# Decisions

When the spec is unclear, agents pick the option that protects privacy more and record it here. One entry per decision, newest at the bottom.

Format: `## D{n} · {agent} · {short title}`, then the question, the choice, and why.

## D1 · A1 · Which server variables are required where

**Question.** The spec lists every server variable but not which ones local development needs. `pnpm dev` must work on a fresh clone, and a missing variable must still stop the server.

**Choice.** `server/src/env.ts` picks a profile from what Vercel sets (`VERCEL_ENV`), and requires:

| Variable | Local (`pnpm dev`, CI, tests) | Vercel preview | Vercel production |
| --- | --- | --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | required | required | required |
| `JOIN_TICKET_SECRET`, `CARD_URL_SECRET`, `CRON_SECRET` | required | required | required |
| `ANTHROPIC_API_KEY`, `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` | optional | required | required |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID` | optional (all four or none) | optional (all four or none) | required |
| `POSTHOG_KEY`, `SENTRY_DSN` | optional | optional | optional |
| `ALLOW_TEST_LOGIN` | optional, local Supabase only | refused | refused |

On Vercel the server also refuses a localhost or non-https `SUPABASE_URL`, the local Supabase demo keys, the placeholder secrets from `.env.example`, and `ALLOW_TEST_LOGIN`. Everywhere, it refuses a service key in the anon slot (and the reverse), the same secret reused for two jobs, and secrets under 32 random bytes. A Vercel deploy with no `VERCEL_ENV` counts as a preview.

**Why.** Previews are reachable from the internet, so they get moderation and rate limits like production. Push isn't a privacy control, so previews can run before the Apple account exists. The checks run in `next.config.ts`, so `next dev`, `next build` and `next start` all stop before serving anything, and again in `instrumentation.ts` in case the runtime env differs from the build's. Messages name the variable and what's wrong, never its value.

## D2 · A1 · Local Supabase keys in `.env.example`

**Question.** Should `.env.example` carry working local values?

**Choice.** Yes for the local Supabase URL and its publishable and secret keys, which are the same public demo keys on every machine and only reach a Supabase on 127.0.0.1. The three signing secrets are placeholders marked `local-dev-only`; `pnpm env:setup` replaces them with fresh random ones and copies the real keys from `supabase status`. D1's Vercel checks reject all of these values.

**Why.** It makes a fresh clone work with one copy, while nothing in the file is a real secret or can reach real data.

## D3 · A1 · Checking access tokens with Supabase on every request

**Question.** Verify Supabase access tokens locally (JWKS, fast) or ask Supabase Auth (`auth.getUser`, one network call)?

**Choice.** `requireUser` asks Supabase Auth on every request, after cheap local checks that reject malformed, expired or non-user tokens without a network call. It also refuses anonymous Supabase users and banned users, and answers 503 (not 401) if Auth is unreachable or slower than 3 seconds, so the app doesn't sign people out on a blip.

**Why.** A deleted, banned or signed-out account stops working immediately instead of up to an hour later when its token expires. If deck latency ever needs it (B4's 300 ms p95), switch to local JWKS verification plus a short cache, and record the trade-off here.

## D4 · A1 · 401, 404 and malformed IDs

**Question.** P11 says not-allowed is 404. What about no sign-in, and IDs that aren't valid UUIDs?

**Choice.** No or bad sign-in is 401 for every route, decided before anything is looked up, so it reveals nothing about any resource. A path ID that fails validation is 404, like any other ID that names nothing you can see. The route helper turns any 403 into the exact same 404 body, and there's no `forbidden()` helper. Unknown `/api` paths get the same JSON 404. Dev-only routes (`/api/dev/*`) are a 404 unless test sign-in is on.

## D5 · A1 · Replies carry only contract fields

**Question.** What happens when a handler returns more than the contract declares?

**Choice.** The route helper parses every JSON reply with the contract's zod schema and sends the parsed result, so undeclared fields are dropped before they leave the server. A reply that doesn't match is a 500 with a generic body; the log names the operation and the failing field paths, never the values. A handler may return its own `Response` only where the contract says `raw` (images, HTML, the link file).

**Why.** It turns P1 from a convention into something a stray `select *` can't break.

## D6 · A1 · Test sign-in has three locks

**Choice.** `POST /api/dev/test-login` only exists when `ALLOW_TEST_LOGIN` is on, the profile is local, and `SUPABASE_URL` is a local address. env.ts refuses the other combinations at startup, and `proxy.ts` answers 404 for `/api/dev/*` otherwise. B1 still compiles the client side out of Release builds.

## D7 · A1 · Logs and Sentry collect nothing personal

**Choice.** All server code logs through `logger` (`server/src/server/log.ts`), which writes JSON lines and redacts any field whose name contains words like `lat`, `lng`, `location`, `accuracy`, `name`, `email`, `body`, `message`, `text`, `token`, `photo` or `ip`. ESLint forbids `console` elsewhere. The route helper logs only the operation, method, status and time. Sentry runs only when `SENTRY_DSN` is set, with every `dataCollection` option off (no headers, cookies, bodies, query strings, user info or stack-frame variables), and a `beforeSend` that keeps only the request's method and path. No source maps are uploaded yet.

**Why.** P2 says coordinates are never logged. Redaction by field name is a safety net under the rule "log IDs and outcomes only", and stack-frame variables are the easiest way for a coordinate to reach Sentry by accident.

## D8 · A1 · No CORS

**Choice.** The API sends no CORS headers. The app is native and the admin web is same-origin, so no other website can call the API from a browser with someone's session.

## D9 · A1 · Vercel deploys from GitHub Actions

**Choice.** `.github/workflows/vercel.yml` builds and deploys with the Vercel CLI: a preview for every PR (its URL posted on the PR) and production for main. `server/vercel.json` turns off Vercel's own Git deploys so nothing deploys twice. The workflow skips cleanly until the Vercel secrets exist.

**Why.** The build runs our env validation with the target environment's variables, so a deploy with a missing variable fails loudly instead of going live.
