# Wave 0 · Foundations

Three agents in parallel. Wave 1 starts only after Checkpoint 1.

## A1 · Integrator and repo

**Mission.** Create the monorepo, CI and server skeleton, then stay on as Integrator for the whole build.

**Read first.** All of Build plan. In the Technical spec: Stack, Repo layout, API contract, Environment and secrets, Testing and definition of done.

**You own.** The repo root, `AGENTS.md`, `docs/` (except `CONTRACTS.md`), `.github/`, the `server/` skeleton (app layout, `src/env.ts`, `src/server/auth`, the route helper, middleware), and `scripts/` except `sim.sh`, `codegen.sh` and `e2e/`.

**Don't touch.** `supabase/`, `contracts/`, `ios/`.

**Build.**

1. A pnpm workspace with `server`: Next.js App Router, TypeScript strict, ESLint, Prettier, Vitest.
2. `server/src/env.ts`, which validates every server variable with zod, plus `.env.example`.
3. `server/src/server/auth`: check the Supabase access token on every API route, with a `requireUser(req)` helper.
4. A typed route helper that validates requests and responses against the generated contract schemas and turns not-allowed into 404 (P11).
5. A stub for every endpoint in the API contract that answers 501, so each owner just fills theirs in.
6. `AGENTS.md`: the rules and privacy invariants from Build plan, word for word, the ownership map from every brief, and every command.
7. The exported spec committed as `docs/SPEC.md`, plus empty `HANDOFFS.md` and `DECISIONS.md`.
8. GitHub Actions. An Ubuntu job: server typecheck, lint and tests, and pgTAP with the Supabase CLI. A macOS job: xcodegen, then iOS build and tests on a Simulator.
9. Vercel linked, with a preview deploy for every PR.

**Done when.**

- [ ] `pnpm dev` serves the server locally, and every contract endpoint answers 501
- [ ] CI is green on main, with both jobs
- [ ] A missing environment variable stops the server with a clear message
- [ ] `AGENTS.md` lists an owner for every folder

**Hand off.** The preview URL, the commands and the ownership map in `docs/HANDOFFS.md`. Then switch to Integrator mode: review and merge PRs in the order in Build plan, keep main green, and regenerate clients after every contract change.

## A2 · Contracts and database

**Mission.** Write the database and the API contract that every other agent codes against.

**Read first.** In the Technical spec: Data model, Database functions, API contract, Events and push, Core rules and numbers. In Build plan: Privacy invariants.

**You own.** `supabase/`, `contracts/`, `scripts/codegen.sh`, `docs/CONTRACTS.md`, and the generated folders `server/src/contracts` and `ios/Packages/GlowKit/Sources/APIClient/Generated`.

**Don't touch.** Anything else.

**Build.**

1. Migration `0001_a2_init.sql`: enums, every table in the data model, constraints, and indexes (check-ins by room and expiry, taps by room and target, matches by pair).
2. Row level security on every table, with no client policies, so the app can never read a table directly. Realtime authorization: a person may join only `user:{their id}`, and `room:{id}` only with an active check-in there.
3. Every SQL function in Database functions: security definer, a fixed search\_path, and an advisory lock on the pair inside `record_tap`.
4. Private storage buckets `profile-photos` and `room-cards`.
5. `contracts/openapi.yaml` for every endpoint, with request and response schemas, error shapes and examples. Plus `contracts/events.json` and `contracts/constants.json`.
6. `scripts/codegen.sh`: the Swift client with swift-openapi-generator, TypeScript types and zod schemas from the same file, and Swift and TypeScript constants from `constants.json`. CI fails if generated files are stale.
7. pgTAP tests for every rule in Core rules and numbers.
8. `seed.sql` for local development: one room centered on the venue, its meeting spots, and test people clearly marked as test data.

**Done when.**

- [ ] `supabase db reset` runs clean and seeds
- [ ] pgTAP: a signed-in person can't read or write any table directly
- [ ] pgTAP: 50 pairs tapping each other at the same moment make exactly 50 matches
- [ ] pgTAP: the tap cap, show me in both directions, blocks in both directions, and expiry all hold
- [ ] Both generated clients compile, and CI catches stale codegen

**Hand off.** `docs/CONTRACTS.md`, with one line per endpoint and event. After Checkpoint 1, contract changes go through A1.

## A3 · iPhone app skeleton

**Mission.** Create the iOS project so nine agents can build features in parallel without stepping on each other.

**Read first.** In the Technical spec: Stack, Repo layout, iOS modules and owners, Simulator workflow, Environment and secrets.

**You own.** `ios/project.yml`, the app target in `ios/Glow`, `ios/Packages/GlowKit/Package.swift`, the AppCore module, the APIClient wrapper (not its Generated folder), `scripts/sim.sh`, `ios/fixtures/` (except push payloads, which B5 adds), `.swiftlint.yml` and `.swiftformat`.

**Don't touch.** Other GlowKit modules, beyond creating each one's folder with a placeholder file.

**Build.**

1. XcodeGen `project.yml`: the Glow app target (iOS 17 minimum, Swift 6, strict concurrency), the GlowLiveActivity widget extension, unit and UI test targets, and Debug and Release configurations with xcconfig files. Add the generated `.xcodeproj` to `.gitignore`.
2. Capabilities and entitlements: Push Notifications, Sign in with Apple, Associated Domains (`applinks:{DOMAIN}`), Time Sensitive Notifications, and the remote notification background mode. Info.plist purpose strings for the camera, photo picker and location. A `glow://` link scheme in Debug only.
3. The GlowKit local package with every module from the spec, each with a placeholder view and one test, so the whole graph compiles on day one.
4. AppCore: a Route enum for every screen, a dependency container where every service is a protocol, and preview mocks for each service.
5. The APIClient wrapper: base URL from config, the Bearer token from Session, retries when the network drops, and 404 mapped to a not-found error.
6. Root navigation that moves between onboarding, rooms, matches and settings by Route, and handles incoming links.
7. `scripts/sim.sh` with every command in Simulator workflow.
8. A `PrivacyInfo.xcprivacy` privacy manifest and a placeholder app icon.

**Done when.**

- [ ] `scripts/sim.sh setup`, `build` and `install` run the app on Glow A and Glow B
- [ ] `scripts/sim.sh scan demo` opens the app on the room route
- [ ] `scripts/sim.sh push A match_created` shows a notification
- [ ] Every module builds and has one passing test
- [ ] Running xcodegen twice gives the same project, and no `.xcodeproj` is in git

**Hand off.** In `docs/HANDOFFS.md`: how to add a file to a module, how to add a route, and how to run one module's tests on its own.
