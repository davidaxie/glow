# AGENTS.md

Glow is a native iPhone app that lets two people in the same room find out, privately, that they noticed each other. 24 agents build it in five waves. This file is the rulebook every agent reads first.

Read in this order: `AGENTS.md` (this file), [`docs/SPEC.md`](docs/SPEC.md), `contracts/openapi.yaml`, `contracts/events.json` and `contracts/constants.json`, [`docs/HANDOFFS.md`](docs/HANDOFFS.md), then your brief in [`docs/briefs/`](docs/briefs/).

The two sections below are copied word for word from [`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md). Don't edit them here; they change only when the build plan does.

## Rules every agent follows

A1 copies these into `AGENTS.md` word for word.

- **Read first.** In order: `AGENTS.md`, `docs/SPEC.md`, `contracts/`, `docs/HANDOFFS.md`, then your brief.
- **Branches.** Use `w{wave}/{agent id}-{short name}`, for example `w1/b3-checkin`. Open a draft PR in your first hour and push often.
- **Ownership.** Edit only the paths you own. If you need something elsewhere, add a request under the owner's ID in `docs/HANDOFFS.md`, or open a tiny PR labeled `cross-owner` and tag the owner.
- **Contracts are law.** Change `contracts/` only in a PR labeled `contract-change` that updates `openapi.yaml`, regenerates both clients and updates the spec. A1 approves.
- **Migrations.** Never edit a merged migration. Add a new one named `NNNN_{agent id}_{what}.sql`.
- **Xcode project.** Never hand-edit the `.xcodeproj`. Change `ios/project.yml` and run `xcodegen`.
- **Mocks.** If something you depend on isn't merged, mock it using the generated contract types. On iOS, that's a protocol plus a mock in your module. On the server, a stub module.
- **Secrets.** None in code. Server secrets come from `server/src/env.ts`. The app only ever holds the Supabase anon key and the API URL.
- **Analytics and errors.** A1 sets up Sentry on the server. A3 sets up Sentry and PostHog in the app behind an Analytics protocol in AppCore. Each feature logs its own key moments through that protocol, never with names, photos, coordinates or message text.
- **Proof.** Every PR passes build, lint and tests in CI. iOS UI PRs include Simulator screenshots of every new screen and a short screen recording.
- **Unclear spec.** Pick the option that protects privacy more, write it in `docs/DECISIONS.md`, and keep going.
- **Done.** Every box under Done when is true, and `docs/HANDOFFS.md` says what you built, what's still mocked and what the next wave needs.

## Privacy invariants

No agent may weaken these to save time. Each one has an automated test and an owner, and D2 tries to break all of them in Wave 3.

| ID | Rule | How it's tested | Owner |
| --- | --- | --- | --- |
| P1 | Before a mutual match, nothing the app receives (API, realtime or push) contains another user's ID, name or face photo. | Contract tests on every endpoint, plus a proxy scan of all traffic during the end-to-end run | A2, D2 |
| P2 | User coordinates are never stored or logged. Only pass or fail is kept. | Logger spy tests on the join route, plus a database column audit | B2 |
| P3 | Only face-blurred card photos leave the phone. | Unit test on the upload payload, plus the end-to-end traffic check | B3 |
| P4 | Every image is checked per request. There are no public storage links. | Storage read with the anon key fails; expired signed links fail | B3, D2 |
| P5 | One-sided taps are never revealed by any response, count or event. | Contract tests | B4 |
| P6 | Lock screen text never includes a name. | Snapshot tests of every push payload | B5 |
| P7 | Blocks apply both ways, everywhere, within 5 seconds. | Database tests plus end to end | B8 |
| P8 | Paused or departed people leave every deck within 5 seconds. | End to end | B8, C1 |
| P9 | Card photos and check-ins are deleted within 10 minutes of expiring. | Cron test | B8 |
| P10 | Nobody under 18 can finish onboarding. | Unit test plus UI test | B1 |
| P11 | Asking for something you're not allowed to see returns 404, never 403, so its existence never leaks. | Contract tests | Every API owner |
| P12 | The deck blurs while the screen is recorded or mirrored, and screenshots of it are logged. | UI test with screen capture faked | C1 |

## Ownership map

Edit only the paths you own. For anything else, add a request under the owner's ID in [`docs/HANDOFFS.md`](docs/HANDOFFS.md), or open a tiny PR labeled `cross-owner` and tag the owner. Agents may always add tests and docs inside the paths they own. If a path isn't listed, it's A1's until A1 assigns it.

Agents: A1 Integrator and repo, A2 Contracts and database, A3 iPhone app skeleton. Wave 1: B1 Sign in and onboarding, B2 Rooms and joining, B3 Check-in and private images, B4 Deck and matching, B5 Push, realtime and events, B6 Design system, B7 Admin and room ops, B8 Safety, moderation and cleanup, B9 Release and TestFlight. Wave 2: C1 Deck experience, C2 Mutual moment and reveal, C3 Glow mode, C4 Chat. Wave 3: D1 Integration and end-to-end tests, D2 Security and privacy red team, D3 Device QA, D4 Accessibility, copy and motion, D5 Demo and launch kit. Wave 4: E1 Ultra Wideband, E2 Bluetooth nearby filter, E3 Glow badge.

### Repo root, docs, CI and scripts

| Path | Owner | Notes |
| --- | --- | --- |
| Repo root files (`package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `.gitignore`, `.editorconfig`, `.nvmrc`, `.prettierrc.json`, `.prettierignore`) | A1 | A2 may add codegen devDependencies to the root `package.json` (pre-approved). Any agent's PR may update `pnpm-lock.yaml` for its own dependencies. |
| `AGENTS.md` | A1 | |
| `.swiftlint.yml`, `.swiftformat` | A1 | Built by A3 in Wave 0 |
| `docs/` | A1 | Except the files below |
| `docs/SPEC.md`, `docs/BUILD_PLAN.md`, `docs/briefs/` | A1 | Exported verbatim from the doc. The spec changes only in a `contract-change` PR. |
| `docs/HANDOFFS.md`, `docs/DECISIONS.md` | A1 (structure) | Every agent writes its own section and adds its own decisions |
| `docs/CONTRACTS.md` | A2 | |
| `docs/RELEASE.md` | B9 | |
| `docs/SECURITY_REVIEW.md` | D2 | |
| `docs/DEVICE_QA.md` | D3 | |
| `docs/DEMO.md` | D5 | |
| `docs/shots/` | Every iOS agent | Only screenshots and recordings of your own screens, through `scripts/sim.sh shot` and `record` |
| `.github/` | A1 | |
| `.github/workflows/release-ios.yml` | B9 | |
| `scripts/` | A1 | `env-setup.sh`, `dev-token.sh`, `smoke.sh`, `agent-env.sh`, `db.sh`, plus anything not listed here |
| `scripts/sim.sh` | A1 | Built by A3 in Wave 0. Ask A1 for changes. |
| `scripts/codegen.sh` | A2 | |
| `scripts/e2e/` | D1 | |
| `scripts/seed-demo.ts` | D5 | |
| `hardware/badge/` | E3 | Wave 4 |

### Contracts and database

| Path | Owner | Notes |
| --- | --- | --- |
| `contracts/` (`openapi.yaml`, `events.json`, `constants.json`) | A2 | After Checkpoint 1, only through a `contract-change` PR that A1 approves |
| `supabase/` (`config.toml`, `migrations/`, `tests/`, `seed.sql`) | A2 | |
| `supabase/migrations/NNNN_b4_*.sql` | B4 | New deck and tap tuning migrations. Any other agent who needs a migration asks A2, then names it `NNNN_{agent id}_{what}.sql`. Never edit a merged migration. |

### Server (`server/`)

| Path | Owner | Notes |
| --- | --- | --- |
| `server/package.json`, `server/next.config.ts`, `server/tsconfig.json`, `server/eslint.config.mjs`, `server/vitest.config.ts`, `server/.env.example` | A1 | Owners may add their own dependencies to `server/package.json` |
| `server/vercel.json` | A1 | The `crons` entry is B8's |
| `server/AGENTS.md` | A1 | Generated by `next dev`. Commit it when it changes. |
| `server/app/layout.tsx`, `server/app/page.tsx`, `server/app/api/[...path]/` | A1 | The app layout and the JSON 404 for unknown API paths |
| `server/proxy.ts`, `server/instrumentation.ts` | A1 | Next.js 16 proxy (formerly middleware), and Sentry |
| `server/src/env.ts` | A1 | Every server variable. Ask A1 to add one. |
| `server/src/server/auth/` | A1 | `requireUser`, `requireCron` |
| `server/src/server/http/` | A1 | The route helper and errors |
| `server/src/server/log.ts`, `server/src/server/observability.ts` | A1 | The redacting logger and Sentry helpers |
| `server/tests/` | A1 | Except `server/tests/security/` (D2). Owners put tests in `server/tests/{module}/` or next to their module. |
| `server/src/contracts/` | A2 | Generated. Never hand-edit. |
| `server/app/api/me/route.ts` | Shared | `GET` is B1's export line, `DELETE` is B8's. Each keeps its handler in its own module. |
| `server/app/api/me/**` (profile, photos), `server/app/api/dev/test-login/`, `server/src/server/profiles/` | B1 | Not `pause` and not `DELETE /api/me` |
| `server/app/api/rooms/resolve/`, `server/app/api/rooms/[id]/route.ts` (`GET /api/rooms/:id`), `server/app/api/rooms/[id]/join/`, `server/app/api/rooms/[id]/leave/`, `server/app/r/[slug]/`, `server/app/.well-known/apple-app-site-association/`, `server/src/server/rooms/`, `server/src/server/geo/`, `server/src/server/qr/` | B2 | |
| `server/app/api/rooms/[id]/checkin/`, `server/app/api/cards/[cardId]/image/`, `server/app/api/matches/[id]/photos/[n]/`, `server/src/server/images/` | B3 | |
| `server/app/api/rooms/[id]/deck/`, `server/app/api/rooms/[id]/taps/`, `server/app/api/matches/route.ts` (`GET /api/matches`), `server/src/server/deck/`, `server/src/server/taps/`, `server/src/server/matches/` | B4 | `matches` covers creation and listing |
| `server/app/api/devices/**`, `server/src/server/notify/` | B5 | |
| `server/app/admin/**`, `server/app/display/[slug]/`, `server/app/api/admin/**`, `server/src/server/admin/` | B7 | |
| `server/app/api/blocks/`, `server/app/api/reports/`, `server/app/api/me/pause/`, `DELETE` in `server/app/api/me/route.ts`, `server/app/api/abuse/capture/`, `server/app/api/cron/purge/`, `server/src/server/moderation/`, `server/src/server/safety/`, `server/src/server/ratelimit/` | B8 | |
| `server/app/api/matches/[id]/route.ts` (`GET /api/matches/:id`), `server/app/api/matches/[id]/choice/`, `server/src/server/choice/` | C2 | |
| `server/app/api/matches/[id]/glow/**`, `server/src/server/glow/` (including `words.ts`) | C3 | |
| `server/app/api/matches/[id]/messages/`, `server/app/api/matches/[id]/unmatch/`, `server/src/server/chat/` | C4 | |
| `server/tests/security/` | D2 | Fixes go through PRs to each owner |
| `server/app/api/matches/[id]/ni-token/` | E1 | Wave 4 |
| `server/app/api/badges/**`, `server/src/server/badges/` | E3 | Wave 4 |

### iPhone app (`ios/`)

Module code lives in `ios/Packages/GlowKit/Sources/{Module}/` and its tests in `ios/Packages/GlowKit/Tests/{Module}Tests/`. Feature modules depend only on AppCore, DesignSystem and the service modules, never on each other.

| Path | Owner | Notes |
| --- | --- | --- |
| `ios/project.yml`, `ios/Glow/` (app target), `ios/GlowTests/`, `ios/Packages/GlowKit/Package.swift` | A1 | Built by A3 in Wave 0. Ask A1 under **For A1** in `docs/HANDOFFS.md` for a dependency, target, capability or build setting. Signing settings in `project.yml` are shared with B9. Never hand-edit the `.xcodeproj`. |
| `ios/` (anything not listed below), `ios/Packages/GlowKit/` (package files outside the module folders) | A1 | Built by A3 in Wave 0 |
| AppCore, the APIClient wrapper | A1 | Built by A3 in Wave 0. Not `Sources/APIClient/Generated`, and not the service protocols and mocks below. |
| `AppCore/Services/SessionService.swift`, `AppCore/Mocks/PreviewSessionService.swift` | B1 | From Wave 1, each service owner owns its protocol and its mock in AppCore, and changes both together (D40) |
| `AppCore/Services/LocationService.swift`, `AppCore/Mocks/PreviewLocationService.swift` | B2 | D40 |
| `AppCore/Services/ImagingService.swift`, `AppCore/Mocks/PreviewImagingService.swift` | B3 | D40 |
| `AppCore/Services/PushService.swift`, `AppCore/Services/RealtimeService.swift`, `AppCore/Mocks/PreviewPushService.swift`, `AppCore/Mocks/PreviewRealtimeService.swift` | B5 | D40 |
| `ios/Packages/GlowKit/Sources/APIClient/Generated/` | A2 | Generated. Never hand-edit. |
| `ios/fixtures/` | A1 | Built by A3 in Wave 0. Except `ios/fixtures/push/` (B5). |
| DesignSystem, the app icon, the launch screen assets | B6 | |
| Session, FeatureOnboarding, FeatureSettings | B1 | |
| Location, FeatureRooms | B2 | |
| Imaging, FeatureCheckIn | B3 | |
| Push, GlowRealtime (the spec's Realtime module), `ios/fixtures/push/` | B5 | It's GlowRealtime because supabase-swift already has a module named Realtime (D41) |
| FeatureSafety | B8 | |
| `ios/fastlane/` | B9 | |
| FeatureDeck | C1 | |
| FeatureMatch | C2 | |
| FeatureGlow, LiveActivityShared (the Live Activity attributes the app and the widget extension share, D41), `ios/GlowLiveActivity/` (the widget extension) | C3 | E1 owns a `Precision` folder inside FeatureGlow in Wave 4, by agreement with C3 |
| FeatureChat | C4 | |
| `ios/GlowUITests/` | D1 | D1 may make small fixes anywhere through PRs labeled `integration`, telling the owner in `docs/HANDOFFS.md` |
| `Localizable.xcstrings` in every module | D4 | Accessibility fixes go through PRs to each owner |
| Proximity | E2 | Wave 4. The `nearbyOnly` deck filter is a contract change. |

## Commands

Run everything from the repo root. One-time setup on a Mac:

```
brew install xcodegen swiftlint swiftformat
pnpm install
pnpm db:start                       # supabase start: local database, auth, storage and realtime
pnpm env:setup                      # writes server/.env.local from server/.env.example, with fresh secrets
pnpm dev                            # local API on http://localhost:3000
```

The spec's `pnpm --filter server dev` and `supabase start` work too; `pnpm dev` and `pnpm db:start` are shortcuts for them. The local Supabase uses ports 54420 to 54424 (API on `http://127.0.0.1:54421`), set in `supabase/config.toml`.

| Command | What it does |
| --- | --- |
| `pnpm dev` | Next.js dev server for `server/` on port 3000. Stops at once, naming each variable, if the environment is wrong. |
| `pnpm build`, `pnpm start` | Production build and server |
| `pnpm typecheck` | `next typegen` then `tsc --noEmit` |
| `pnpm lint` | ESLint with no warnings allowed |
| `pnpm format`, `pnpm format:check` | Prettier, for everything except iOS, generated code, `supabase/` and `contracts/` |
| `pnpm test` | Vitest |
| `pnpm check` | typecheck, lint, format check and tests: what CI's Ubuntu job runs on the server |
| `pnpm ci:local <ID> [--server-only]` | Both CI jobs on this Mac, in your agent slot, with a one-line summary for your PR (see "While GitHub Actions is down") |
| `pnpm env:setup [--force] [--test-login]` | Writes `server/.env.local`. Copies keys from `supabase status` if it's running. `--test-login` turns on `ALLOW_TEST_LOGIN` (local only). |
| `pnpm dev:token` | Prints an access token for a new throwaway test person on the local Supabase |
| `pnpm smoke` | Calls every operation in the contract on a running server. Signed out, user routes must answer 401; with `GLOW_TOKEN=$(pnpm -s dev:token)`, each route must answer 501 (a stub) or a status the contract declares for it, never a 500. Uses `GLOW_API` (set by `agent-env.sh`). |
| `pnpm stubs` | Adds a 501 stub route for any contract operation without one (A1 runs it after contract changes) |
| `pnpm codegen` | `scripts/codegen.sh` (A2): Swift client, TypeScript types and zod schemas, and constants from `contracts/` |
| `pnpm db:start`, `pnpm db:stop`, `pnpm db:reset`, `pnpm db:test` | `supabase start`, `stop`, `db reset` (migrations plus seed) and `test db` (pgTAP) |
| `scripts/sim.sh setup [A]` | Create and boot two Simulators, Glow A and Glow B. `setup A` boots only Glow A. |
| `scripts/sim.sh build` | xcodegen, then xcodebuild for the Simulator |
| `scripts/sim.sh install` | Install the Debug app on both |
| `scripts/sim.sh at venue`, `scripts/sim.sh at away` | Move both to the seeded room's center, or 2 km away |
| `scripts/sim.sh photos` | Add fixture outfit photos to both photo libraries |
| `scripts/sim.sh scan demo` | Open the demo room's link, as if its QR was scanned |
| `scripts/sim.sh push A match_created` | Send a fixture notification to Glow A |
| `scripts/sim.sh shot deck-empty` | Save a screenshot of both to `docs/shots/` |
| `scripts/sim.sh record` | Record both screens until you stop it |
| `scripts/sim.sh test` | Unit and UI tests on Glow A |
| `scripts/sim.sh teardown` | Shut down and delete this agent's Simulators |
| `eval "$(scripts/agent-env.sh <ID>)"` | This agent's own Simulator names, server port and API URL. `--own-db` adds an own Supabase. See the next section. |

Export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before `xcodebuild` or `xcrun` if `xcode-select` points at the Command Line Tools.

## Many agents on one Mac

Up to nine agents build and test on the same Mac at once. Each works in its own git worktree, so builds (`ios/build`, `.next`) never collide; these rules keep the shared Simulators, ports and database apart.

1. **Start every shell with your agent environment:** `eval "$(scripts/agent-env.sh <your ID>)"`. It sets your own Simulator names (`GLOW_SIM_A="Glow A (B1)"`, `GLOW_SIM_B="Glow B (B1)"`), your server port (`PORT`, from the table below) and the matching `GLOW_API` and `GLOW_API_BASE_URL`. Then `pnpm dev` serves your worktree's server on your port, `scripts/smoke.sh` checks it, and `scripts/sim.sh build` points the Debug app at it.
2. **Boot only Glow A** (`scripts/sim.sh setup A`) unless the test needs both people. Each booted Simulator costs memory and CPU every other agent shares.
3. **Never run `supabase db reset`, `supabase stop` or `supabase start` on the shared `glow` stack** (API 54421, DB 54422). Other agents are using it. `pnpm db:reset` and `pnpm db:stop` refuse when `GLOW_AGENT_ID` is set. If you add a migration or need a reset, take your own stack: `eval "$(scripts/agent-env.sh <ID> --own-db)"` copies your worktree's `supabase/` into `.agent-state/<id>/`, starts it as `glow-<id>` on your own port block, and exports its `SUPABASE_URL` and keys (your server and `sim.sh build` use them). `--own-db --reset` reapplies your migrations and seed; `scripts/agent-env.sh <ID> --stop-db` stops it. `pnpm db:*` follows `GLOW_SUPABASE_WORKDIR`, so it targets your stack.
4. **Clean up** with `scripts/sim.sh teardown` (and `--stop-db` if you took a stack) when your work is merged.
5. **Prove iOS work locally while your PR is a draft.** Run `scripts/sim.sh build`, `test` and `lint`, and attach `scripts/sim.sh shot` screenshots to the PR.
6. **Never poll GitHub in a loop.** Every agent shares one GitHub token, and a polling loop trips GitHub's rate limit for everyone. To wait for CI, run one `gh pr checks <n> --watch --interval 60` in the background and let it tell you when it's done, or check once after doing other work. Never more than one watcher at a time.
7. **Decision IDs carry your agent ID.** In `docs/DECISIONS.md`, add a `## {ID} · {your name}` section and number your decisions inside it: `### B2-D1 · {short title}`, `### B2-D2`, and so on, so parallel PRs never collide. `D1` to `D56` keep their numbers.

| Agents | Server port | Own Supabase API (`--own-db`) |
| --- | --- | --- |
| A1, A2, A3 | 3091, 3092, 3093 | 55011, 55021, 55031 |
| B1 to B9 | 3101 to 3109 | 55111 to 55191 (B1 is 55111, B2 is 55121, ...) |
| C1 to C4 | 3111 to 3114 | 55211 to 55241 |
| D1 to D5 | 3121 to 3125 | 55311 to 55351 |
| E1 to E3 | 3131 to 3133 | 55411 to 55431 |

Port 3000 and the shared stack's 544xx ports stay for the main checkout. `scripts/agent-env.sh --list` prints the whole table.

## Writing a server route

Every endpoint in the contract already has a route file that answers 501 (when a contract change adds endpoints, A1 runs `pnpm stubs` to add theirs). To build yours, replace `notImplemented` with a handler, and keep the logic in your own module under `server/src/server/`:

```ts
// server/app/api/matches/[id]/route.ts  (C2)
import { route } from '@/server/http';
import { getMatchFor } from '@/server/choice/get-match';

export const GET = route('getMatch', getMatchFor);
```

```ts
// server/src/server/choice/get-match.ts
import { notFound, type RouteHandler } from '@/server/http';

export const getMatchFor: RouteHandler<'getMatch'> = async ({ user, params }) => {
  const match = await loadMatch(params.id, user.id);
  if (!match) throw notFound(); // also when it exists but isn't theirs (P11)
  return { status: 200, body: match };
};
```

The helper reads the operation from the generated contract and, before your handler runs, checks sign-in (401, or 503 if Supabase Auth is down), turns a malformed path ID into 404, and validates the query and body (400, with field paths but never the values sent). After it runs, it validates your reply and sends only the fields the contract declares. A reply that breaks the contract becomes a 500, so test your happy path.

- Throw `notFound()`, `badRequest()`, `conflict(code, message)`, `unprocessable(code, message, { reason })`, `rateLimited()` or `unavailable()` from `@/server/http`. Codes are the contract's `ErrorCode` enum (409 `tap_limit_reached`, 422 `not_in_room` and so on; `docs/CONTRACTS.md` maps database errors to them). There is no `forbidden()`: a 403 is always sent as 404 (P11).
- Times go out as `2026-10-24T20:15:00.000Z`. The database functions already return that; rows read straight from tables come back as `+00:00`, so send `new Date(value).toISOString()`, or the contract check turns the reply into a 500.
- Log with `logger` from `@/server/log`, never `console`. It redacts fields like `lat`, `name` and `body`, but don't rely on that: log IDs, counts and outcomes only (P2).
- Read configuration with `getEnv()` from `@/env`, never `process.env`. ESLint enforces both.
- Every API response is `Cache-Control: no-store`. Raw responses (images, HTML, the link file) are only allowed where the contract says so.
- Next.js 16 has breaking changes from what you may know (middleware is now `proxy.ts`, route `params` are a Promise, `next lint` is gone). Read `server/node_modules/next/dist/docs/` before relying on memory.

## Pull requests and integration

### While GitHub Actions is down

GitHub Actions isn't starting jobs (Needs David: billing), so local CI is the merge gate until A1 says otherwise.

1. Rebase on `main`, commit everything, then run `scripts/ci-local.sh <your ID>` (or `pnpm ci:local <your ID>`) from your worktree. It runs both CI jobs in your agent slot: your own Supabase stack (`--own-db --reset`, so the database matches your migrations), your port, and `Glow A ({ID})`. It takes about 10 minutes. Add `--server-only` only when the PR changes nothing in `ios/`, `contracts/`, `scripts/sim.sh` or `scripts/codegen.sh`.
2. Post its last line, the summary, as a PR comment, for example `ci-local B1 3f2a9c1 (rebased on main 9de2799): ubuntu pass, macos pass, 9m40s`.
3. A PR is mergeable when its author's latest summary names the PR's current head SHA, says `rebased on main`, and shows `ubuntu pass` and `macos pass` (or `macos skipped` with `--server-only`, when allowed). A1 merges. Any push after the summary needs a new run.


- Branch `w{wave}/{agent id}-{short name}`, draft PR in your first hour, push often.
- CI runs two jobs on every PR and on main. **Ubuntu**: install, typecheck, lint, Prettier, Vitest, `next build`, a smoke test of every endpoint, the codegen staleness check, and pgTAP on a local Supabase. **macOS**: SwiftLint, SwiftFormat, xcodegen, then the iOS build and tests on a Simulator.
- A PR is ready when every box of the spec's definition of done is ticked: no warnings under Swift 6 strict concurrency and the server typechecks; SwiftLint, SwiftFormat, ESLint and Prettier pass; new logic has tests and CI is green; new screens have Simulator screenshots, a recording, VoiceOver labels and a Dynamic Type check; no privacy invariant is weakened; `docs/HANDOFFS.md` is updated.
- A1 reviews every PR against this file and merges with a squash, in the order in Build plan. A PR that breaks main gets reverted first and fixed second.
- Contract changes: a PR labeled `contract-change` that updates `contracts/openapi.yaml`, regenerates both clients with `pnpm codegen` and updates `docs/SPEC.md`. A1 approves and regenerates clients on main after merging.
- Preview deploys: every PR gets a Vercel preview through `.github/workflows/vercel.yml`, once the Vercel project is linked.
