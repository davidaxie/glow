# Handoffs

What each agent built, what's still mocked, and what the next wave needs. Requests for another agent go under that agent's ID in **Requests**. Each agent keeps its own section under **Status** up to date. Newest notes go at the top of each section.

## Needs David

Things only David can do. None of these block Wave 0 work locally.

1. **Link Vercel.** Create a Vercel project from `davidaxie/glow` with Root Directory `server` (framework Next.js, Node 24). Then add three GitHub repository secrets: `VERCEL_TOKEN` (a Vercel access token), `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` (both in the project's `.vercel/project.json` after `vercel link`, or in Project Settings). From then on, every PR gets a preview URL posted on it and main deploys to production. You don't need to connect Vercel's Git integration: `server/vercel.json` turns its auto-deploys off, and the workflow deploys instead.
2. **Add the Vercel env vars**, per D1 in `docs/DECISIONS.md`. Preview and production both need `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (from the Supabase cloud project), `JOIN_TICKET_SECRET`, `CARD_URL_SECRET`, `CRON_SECRET` (each from `openssl rand -base64 32`, all different, different per environment), `ANTHROPIC_API_KEY`, `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN`. Production also needs `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` and `APNS_BUNDLE_ID` (B9 makes the .p8 key). `SENTRY_DSN` and `POSTHOG_KEY` are optional. Never set `ALLOW_TEST_LOGIN` on Vercel; the server refuses to start if you do.
3. **Vercel plan for the purge cron.** P9 needs `GET /api/cron/purge` every 5 minutes. Vercel's Hobby plan only runs crons once a day, so the project needs Pro (or B8 needs an outside scheduler that sends `Authorization: Bearer $CRON_SECRET`).
4. **Branch protection on main** (optional, recommended): require the `Ubuntu · server and database` and `macOS · iOS build and tests` checks before merging. A1 didn't change repo settings.
5. **Cloud accounts** from Build plan step 2 (Supabase cloud, Upstash, Anthropic, PostHog, Sentry, Apple Developer). None exist yet; local development doesn't need them.

## Requests

### For A1

### For A2

_From A1, 2026-10-24._

1. **Generated server registry.** The route helper needs one entry per `operationId`, exported from `server/src/contracts` (say `server/src/contracts/operations.ts`) in this shape, which today's placeholder in `server/src/server/http/contract-placeholder.ts` copies:

   ```ts
   export const operations = {
     getMatch: {
       method: 'GET',                       // HttpMethod
       path: '/api/matches/{id}',           // the OpenAPI path
       auth: 'user',                        // 'user' | 'public' | 'cron', from `security`
       params: z.object({ id: z.uuid() }),  // path params, when there are any
       query: z.object({ ... }),            // when there is a query
       body: z.object({ ... }),             // JSON body, or the string 'multipart' for uploads
       maxBodyBytes: 65536,                 // optional
       responses: { 200: MatchSchema, 404: ErrorSchema },  // zod schema, null for no body, 'raw' for images, HTML and the link file
     },
   } as const;
   ```

   The type is `OperationDef` in `server/src/server/http/operation.ts`; import it or match it. Use zod 4 (the workspace has `zod@4.6.7`). Plain `z.object` is fine: the helper sends the parsed reply, so undeclared fields never leave the server.
2. **operationIds.** The stubs use the names in the placeholder (`getMe`, `updateProfile`, `addProfilePhoto`, `deleteProfilePhoto`, `testLogin`, `setPaused`, `deleteAccount`, `registerDevice`, `deleteDevice`, `resolveRoom`, `joinRoom`, `leaveRoom`, `getAppSiteAssociation`, `getRoomWebPage`, `createCheckin`, `getCardImage`, `getMatchPhoto`, `getDeck`, `createTap`, `listMatches`, `getMatch`, `setChoice`, `getGlow`, `markGlowMet`, `cancelGlow`, `listMessages`, `sendMessage`, `unmatch`, `createBlock`, `createReport`, `logCapture`, `runPurge`). Use whatever names you like in `openapi.yaml`; A1 renames the stubs when wiring codegen. Please also define the `/api/admin/*` operations so B7 gets stubs.
3. **Error shape.** The server sends `{ "error": { "code": string, "message": string, "issues"?: [{ "path": string, "code": string, "message": string }] } }` for 400, 401, 404, 409, 413, 415, 429, 500, 501 and 503 (see `server/src/server/http/errors.ts`). Codes: `bad_request`, `unauthorized`, `not_found`, `conflict`, `payload_too_large`, `unsupported_media_type`, `rate_limited`, `internal`, `not_implemented`, `unavailable`. Please use this as the `Error` schema, or tell A1 yours and A1 will match it. There is no 403 anywhere (P11).
4. **Auth in the contract.** Every operation is Bearer-authenticated except: `POST /api/dev/test-login`, `GET /.well-known/apple-app-site-association` and `GET /r/{slug}` (public), and `GET /api/cron/purge` (cron secret, sent as `Authorization: Bearer`). A1 marked `GET /api/cards/{cardId}/image` as Bearer plus B3's signed link; tell A1 if you'd rather it be signed-link only.
5. **Codegen in CI.** The Ubuntu job runs `scripts/codegen.sh` after `supabase start`, then fails if `git diff` shows changes or new untracked files. Please make the script deterministic and runnable on Ubuntu (Swift is on the runner image; tell A1 if you need it on the macOS job instead). Add your codegen devDependencies to the root `package.json` in your PR; that's pre-approved, and `pnpm codegen` already calls your script.
6. **pgTAP in CI** runs `supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta` then `supabase test db`, with CLI 2.122.0 and your `config.toml` ports. Thanks for the port note: `server/.env.example` now uses `http://127.0.0.1:54421`.
7. **Password sign-in stays on locally**, please: `scripts/dev-token.sh` creates a throwaway `@glow.test` user with the admin API and signs in with a password, so CI can smoke-test every endpoint with a real token.

### For A3

_From A1, 2026-10-24._

1. **CI's macOS job** (runner `macos-26`, Xcode 26.6 default, iOS 26.5 simulators including iPhone 17 Pro) skips until `ios/project.yml` exists. Then it runs `brew install xcodegen swiftlint swiftformat`, `swiftlint lint --strict` (if `.swiftlint.yml` exists), `swiftformat --lint .` (if `.swiftformat` exists), `xcodegen generate --spec ios/project.yml`, then `scripts/sim.sh setup`, `scripts/sim.sh build` and `scripts/sim.sh test` with `GLOW_CI=1`. Please make those three work headless on a fresh runner: create Glow A and Glow B on the newest installed iPhone Pro runtime, no signing (`CODE_SIGNING_ALLOWED=NO`), and a non-zero exit on any failure. Without `sim.sh`, CI falls back to `xcodebuild test -scheme Glow -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`, so a scheme named `Glow` that runs the unit tests helps.
2. **Local server for Debug builds.** `pnpm dev` serves `http://localhost:3000`. The local Supabase is `http://127.0.0.1:54421` with the public demo publishable key `sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH` (the same as `server/.env.example`). Debug needs an ATS exception for local networking.
3. **Server errors** reach the app as `{ "error": { "code", "message" } }`. 401 means sign in again, 404 means not found or not yours (map both to your not-found error), 503 means retry, and 429 comes with `Retry-After`.
4. **Ownership.** `AGENTS.md` gives you `ios/` for anything not listed, `ios/GlowTests/` and the package files under `ios/Packages/GlowKit/`. A server test fails if a file in git has no owner in `AGENTS.md`, so tell A1 if you add a top-level folder somewhere else.

## Status

### A1 · Integrator and repo

_2026-10-24, Wave 0._ PR [#1](https://github.com/davidaxie/glow/pull/1) on `w0/a1-repo`.

**Built**

- pnpm workspace (`package.json`, `pnpm-workspace.yaml`) with one package, `server`: Next.js 16.4 App Router, TypeScript 6 strict, ESLint 9 with the Next config, Prettier, Vitest 4. Node 24 (`.nvmrc`).
- `server/src/env.ts`: every server variable validated with zod, with local, preview and production profiles (D1). A wrong environment stops `next dev`, `next build` and `next start` with a message naming each variable. `server/.env.example` describes all of them.
- `server/src/server/auth`: `requireUser(req)` checks the Supabase access token with Supabase Auth (D3), `requireCron(req)` checks the cron secret in constant time.
- `server/src/server/http`: the typed route helper, `route(operationId, handler)`. Sign-in from the contract, 404 for malformed IDs and for any 403 (P11), 400 with field paths but no values, only contract fields in replies (P1), `no-store` everywhere, and 500s logged without bodies (P2). See "Writing a server route" in `AGENTS.md`.
- A route file answering 501 for all 32 endpoints in the spec's API contract, a JSON 404 for any other `/api` path, and `proxy.ts` hiding `/api/dev/*` unless test sign-in is on (D6).
- `server/src/server/log.ts` (redacting JSON logger) and Sentry in `server/instrumentation.ts`, off unless `SENTRY_DSN` is set and collecting nothing personal (D7).
- Scripts: `scripts/env-setup.sh`, `scripts/dev-token.sh`, `scripts/smoke.sh`.
- CI (`.github/workflows/ci.yml`) and Vercel deploys (`.github/workflows/vercel.yml`, `server/vercel.json`).
- `AGENTS.md` with the rules and privacy invariants word for word, the ownership map from every brief, and every command. Tests fail if those sections drift from the build plan or if a file in git has no owner.

**Commands**: see the Commands section of `AGENTS.md`. The short version: `pnpm install`, `pnpm db:start`, `pnpm env:setup`, `pnpm dev`, then `pnpm check` before you push.

**Ownership map**: see the Ownership map in `AGENTS.md`.

**Preview URL**: none yet. Vercel isn't linked (Needs David, item 1).

**Still mocked**: the operation registry. `server/src/server/http/contract-placeholder.ts` stands in for A2's generated `server/src/contracts` with the right paths, methods, auth and path params, and empty request and response schemas. A1 swaps it for the generated registry when A2's PR merges, then deletes the placeholder.

**Next wave needs**: build your endpoint by replacing `notImplemented` in its route file (the owner is named at the top of each file). Get a local token with `pnpm -s dev:token`, and check every endpoint with `pnpm smoke`.
