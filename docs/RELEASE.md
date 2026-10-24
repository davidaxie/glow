# Release

Owner: B9. How Glow gets from `main` onto real iPhones through TestFlight, and everything David sets up with Apple first.

**Today:** the pipeline is built and checked as far as it can be without an Apple Developer account. Every step that needs the account is listed in [Apple setup](#apple-setup-for-david) and under **Needs David** in [`HANDOFFS.md`](HANDOFFS.md). Until then the TestFlight job skips with a notice, and `ios/fastlane/ship check` lists what's missing.

## Ship a build

One command, from the repo root:

```
ios/fastlane/ship release
```

It tags `origin/main` as `beta-<UTC time>` (for example `beta-20261024-201500`) and pushes the tag. The **Release iOS** workflow (`.github/workflows/release-ios.yml`) then:

1. Runs the checks that need no Apple account (below).
2. Reads the newest build number on TestFlight and adds 1. Nothing is committed: the number goes into the build through an xcconfig override, and the version stays `MARKETING_VERSION` from `ios/Glow/Config/Shared.xcconfig`.
3. Generates the Xcode project, puts the distribution certificate in a throwaway keychain, installs the two App Store profiles, and archives the Release configuration.
4. Checks the exported `.ipa` before anything leaves the machine (see [What the release lane refuses](#what-the-release-lane-refuses)).
5. Uploads it to TestFlight with the App Store Connect API key and sets What to Test. Internal testers get the build as soon as Apple finishes processing it, usually in 5 to 15 minutes.

The job summary shows the version and build number. **After every release, update the TestFlight link and the build number in B9's section of `docs/HANDOFFS.md`.**

A1's end-of-wave tags (`wave-1-done` and so on) ship the same way. You can also start a run in GitHub: **Actions → Release iOS → Run workflow**, with the lane `beta`, `external` or `status`.

### Other commands

`ios/fastlane/ship` installs fastlane (pinned in `ios/fastlane/Gemfile.lock`) into `ios/build/bundle` the first time, with Homebrew's Ruby (`brew install ruby`).

| Command | Needs the Apple account | What it does |
| --- | --- | --- |
| `ios/fastlane/ship release` | yes | Tag `main` and let CI ship it (above) |
| `ios/fastlane/ship check` | no | Privacy answers match the manifest, beta texts fit, settings agree, and a list of what `beta` still needs. CI runs it on every PR that touches release files. |
| `ios/fastlane/ship test` | no | Unit tests for the lanes' helpers (`ios/fastlane/test`) |
| `ios/fastlane/ship verify_release` | no | Unsigned Release build for a device, then the same checks `beta` runs on the real archive. Run it after changing `project.yml`, `Info.plist`, entitlements or the xcconfigs. |
| `ios/fastlane/ship beta` | yes | Build and upload from this Mac instead of CI. Needs the `ASC_*`, `SUPABASE_*` variables below; the certificate and profiles can be in the login keychain instead of variables. |
| `ios/fastlane/ship external` | yes | Send a build to the **Public** group for external beta review (step 10) |
| `ios/fastlane/ship status` | yes | Latest build, its internal and external state, and the public link |
| `ios/fastlane/ship privacy` | yes | Upload the App Privacy answers. Signs in with your Apple ID, so run it yourself on your Mac. |
| `ios/fastlane/ship privacy_answers` | no | Rewrite `ios/fastlane/app-privacy.json` from the privacy manifest |

## What the release lane refuses

`beta` stops before building if anything below is wrong, with one line per problem naming the fix, and marks each one that only the Apple account, the hosted Supabase project or the web domain can unblock. After building, it checks the exported app and refuses to upload it if:

- the Debug-only `glow://` scheme or any App Transport Security exception is in the Info.plist (D34)
- the API URL isn't `https://{DOMAIN}`, or the Supabase URL isn't a hosted https address
- the Supabase key in the app isn't the anon key: a `sb_secret_` key, a JWT whose role is `service_role`, or the local stack's demo key (AGENTS.md: the app only ever holds the anon key)
- the PostHog key is a personal (`phx_`) key
- any file in the app contains a Supabase secret or service-role key, a private key, an Anthropic key, the Debug-only test sign-in route (D6, D22) or a `GlowDebug…` launch argument
- `aps-environment` isn't `production` (TestFlight push), Associated Domains isn't exactly `applinks:{DOMAIN}`, Sign in with Apple is missing, or `get-task-allow` is on
- the Live Activity extension's version or build number differs from the app's

## Apple setup for David

Do these in order. Nothing here can be done by an agent: it all needs your paid Apple Developer account and your sign-in. Keep every key and password in your password manager, never in git (`.gitignore` already ignores `*.p8`, `*.p12`, `*.mobileprovision` and `*.cer`).

### 1. Join the Apple Developer Program

1. Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll) and enroll (99 USD a year). Free accounts can't use push or TestFlight.
2. When it's active, open [developer.apple.com/account](https://developer.apple.com/account) → **Membership details**, and copy the **Team ID** (10 characters, like `A1B2C3D4E5`).
3. Put it in `ios/Glow/Config/Shared.xcconfig`: `DEVELOPMENT_TEAM = A1B2C3D4E5`. This is the only place the team is set; Debug builds, the release lane and the server's link file all follow it. A1 owns that file, so ask A1 or open a one-line PR labeled `cross-owner`. The Team ID isn't secret (every signed app shows it).

### 2. Register the two bundle IDs

[developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list) → **Identifiers** → **+**.

**The app:**

1. **App IDs** → Continue → **App** → Continue.
2. Description `Glow`. Bundle ID **Explicit**: `com.davidxie.glow`.
3. Under **Capabilities**, check:
   - **Associated Domains** (room QR links open the app)
   - **Push Notifications** (leave the certificate options alone; Glow uses the key from step 3)
   - **Sign In with Apple** (leave "Enable as a primary App ID")
   - **Time Sensitive Notifications** (`glow.started`)
4. Continue → **Register**.

**The Live Activity extension:**

1. **+** → **App IDs** → **App** → Continue.
2. Description `Glow Live Activity`. Bundle ID **Explicit**: `com.davidxie.glow.LiveActivity`.
3. No capabilities. Continue → **Register**.

Live Activities need no capability of their own; they use the app's push.

### 3. Make the push key (.p8) and give it to the server

1. [Keys](https://developer.apple.com/account/resources/authkeys/list) → **+**.
2. Key name `Glow APNs`. Check **Apple Push Notifications service (APNs)**. If there's a **Configure** button, choose environment **Sandbox & Production** and key restriction **Team Scoped (All Topics)**, then Save. Continue → **Register**.
3. **Download** the `AuthKey_XXXXXXXXXX.p8` file. Apple only lets you download it once, so put it in your password manager now. Copy the **Key ID** shown on the page.
4. In Vercel → the Glow project → **Settings → Environment Variables**, add for **Production** (and Preview, if you want pushes from previews):

   | Variable | Value |
   | --- | --- |
   | `APNS_KEY_ID` | the Key ID |
   | `APNS_TEAM_ID` | your Team ID |
   | `APNS_PRIVATE_KEY` | the whole contents of the `.p8` file, `BEGIN` and `END` lines included, pasted as is |
   | `APNS_BUNDLE_ID` | `com.davidxie.glow` |

5. Redeploy production. `server/src/env.ts` refuses to start production without all four, and names whichever is wrong.

Xcode builds register `sandbox` tokens and TestFlight builds `production` ones; the one key works for both.

### 4. Make the distribution certificate

1. Open Xcode → **Settings → Accounts** → **+** → Apple ID, and sign in.
2. Select your team → **Manage Certificates…** → **+** → **Apple Distribution**. Xcode makes the certificate and keeps its private key in your login keychain.
3. Export it for CI: open **Keychain Access** → **login** → **My Certificates** → right-click **Apple Distribution: (your name) (Team ID)** → **Export…** → format **.p12** → save as `glow-distribution.p12` outside the repo, with a long random password. Put both in your password manager.

The certificate lasts a year. When it expires, repeat this step and steps 5 and 8 (the profiles name the certificate).

### 5. Make the two App Store provisioning profiles

[Profiles](https://developer.apple.com/account/resources/profiles/list) → **+**. The names must match exactly: `ios/project.yml` and the Fastfile use them.

1. **Distribution** → **App Store Connect** → Continue.
2. App ID `com.davidxie.glow` → Continue → select the Apple Distribution certificate from step 4 → Continue.
3. Name **`Glow App Store`** → **Generate** → **Download**.
4. Repeat for App ID `com.davidxie.glow.LiveActivity`, named **`Glow Live Activity App Store`**.
5. Double-click both downloaded files so Xcode installs them (only needed for building on your Mac).

If you add a capability later, regenerate both profiles (Edit → Save → Download) and update the GitHub secrets in step 8.

### 6. Create the app in App Store Connect

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Platform **iOS**. Name **Glow** (names are unique across the App Store; if it's taken, try `Glow · Noticed You` or `Glow Rooms`. The home screen still says Glow). Primary language **English (U.S.)**. Bundle ID **com.davidxie.glow**. SKU `glow-ios`. User access **Full Access** → **Create**.
3. Under **App Information**, set the category to **Social Networking**. If App Store Connect asks for an age rating, answer so the result is 18+: Glow meets strangers, has chat and user photos, and refuses anyone under 18.

### 7. Make the App Store Connect API key

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**. The first time, click **Request Access** and accept.
2. **+** (Generate API Key). Name `Glow CI`. Access **App Manager**. That's enough to upload builds and run TestFlight, and nothing more: signing uses the certificate and profiles from steps 4 and 5, so the key never needs Admin.
3. **Generate**, then **Download API Key** (once only) → `AuthKey_YYYYYYYYYY.p8`. Copy the **Key ID** from the row and the **Issuer ID** shown above the table. Password manager again.

### 8. Add the GitHub secrets

In [github.com/davidaxie/glow/settings/secrets/actions](https://github.com/davidaxie/glow/settings/secrets/actions), or with the `gh` commands below from the folder holding the files. `base64 -i file` prints a file as one line.

| Secret | Value | With `gh` |
| --- | --- | --- |
| `ASC_KEY_ID` | API Key ID (step 7) | `gh secret set ASC_KEY_ID` |
| `ASC_ISSUER_ID` | Issuer ID (step 7) | `gh secret set ASC_ISSUER_ID` |
| `ASC_KEY` | the API key `.p8` contents (or base64 of them) | `gh secret set ASC_KEY < AuthKey_YYYYYYYYYY.p8` |
| `DIST_CERT_P12_BASE64` | base64 of the `.p12` (step 4) | `base64 -i glow-distribution.p12 \| gh secret set DIST_CERT_P12_BASE64` |
| `DIST_CERT_PASSWORD` | the `.p12` password | `gh secret set DIST_CERT_PASSWORD` |
| `PROFILE_APP_BASE64` | base64 of `Glow_App_Store.mobileprovision` | `base64 -i Glow_App_Store.mobileprovision \| gh secret set PROFILE_APP_BASE64` |
| `PROFILE_LIVE_ACTIVITY_BASE64` | base64 of the Live Activity profile | `base64 -i Glow_Live_Activity_App_Store.mobileprovision \| gh secret set PROFILE_LIVE_ACTIVITY_BASE64` |
| `SUPABASE_URL` | the hosted Supabase project URL, `https://<ref>.supabase.co` | `gh secret set SUPABASE_URL` |
| `SUPABASE_ANON_KEY` | its anon (publishable) key. **Never** the service role or secret key: the lane refuses those | `gh secret set SUPABASE_ANON_KEY` |
| `POSTHOG_KEY` (optional) | the PostHog project key, `phc_…` | `gh secret set POSTHOG_KEY` |
| `SENTRY_DSN` (optional) | once Sentry is back in the app ([below](#crash-reports-sentry)) | `gh secret set SENTRY_DSN` |
| `GLOW_REVIEW_FIRST_NAME`, `GLOW_REVIEW_LAST_NAME`, `GLOW_REVIEW_EMAIL`, `GLOW_REVIEW_PHONE` | who Apple's beta reviewers contact (you). Kept out of git on purpose. | `gh secret set GLOW_REVIEW_PHONE` and so on |
| `GLOW_FEEDBACK_EMAIL` | where testers' feedback goes; testers see it | `gh secret set GLOW_FEEDBACK_EMAIL` |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POSTHOG_KEY` and `SENTRY_DSN` may be repository **variables** instead; they ship inside the app anyway. Two optional variables: `GLOW_REVIEW_VIDEO_URL` (a recording of the full loop for Apple's reviewers) and `GLOW_PRIVACY_POLICY_URL` (default `https://{DOMAIN}/privacy`).

For `ios/fastlane/ship beta` on your Mac, export the same names in your shell (use `ASC_KEY_PATH=/path/to/AuthKey_YYYYYYYYYY.p8` instead of `ASC_KEY` if you like). Without the `DIST_CERT_*` and `PROFILE_*` variables it uses the certificate and profiles already in your keychain from steps 4 and 5.

### 9. Ship the first build and make the internal group

1. Make sure `DEVELOPMENT_TEAM` and `GLOW_WEB_DOMAIN` are set in `Shared.xcconfig` on `main`, and B9's signing PR (#17) is merged.
2. Run `ios/fastlane/ship release`, and wait for the workflow to go green (about 15 to 25 minutes).
3. App Store Connect → Glow → **TestFlight** → **Internal Testing** → **+** → name `Glow team`. Keep **Enable automatic distribution** checked, so every new build reaches the group without anyone clicking.
4. Add testers: yourself, and Robin. Robin first needs an App Store Connect user: **Users and Access** → **+** → Robin's Apple ID email, role **Developer**, leave "Access to Certificates, Identifiers & Profiles" off, apps: Glow only. Once Robin accepts, add Robin to `Glow team`.
5. **Stage phones.** Internal testers install on up to 30 devices each. Install the **TestFlight** app on both stage phones, sign the phone's App Store into your or Robin's Apple ID (Settings → your name → Media & Purchases), and open the invite there. Or wait for the public link (step 11), which needs no Apple ID of yours.
6. On your iPhone: open the TestFlight invite email, install Glow, open it. **This ticks the first Done-when box.**
7. **Push through production:** with two iPhones on the TestFlight build, signed in as two people, join a room, tap each other, and lock both phones. Both should show "Someone you noticed noticed you back." This needs B5's sender and the `APNS_*` variables from step 3. **That ticks the second box.**

### 10. Submit a build for external beta review

As soon as sign-in (B1) and room joining (B2) work on `main`. Apple's first external review takes about a day, and it runs while everyone keeps building.

1. TestFlight → **External Testing** → **+** → name exactly **`Public`** → Create. Don't add a build by hand.
2. Fill in **App Privacy** with the answers below ([App Privacy answers](#app-privacy-answers)), and the Privacy Policy URL (`https://{DOMAIN}/privacy`; the [draft is below](#privacy-policy-draft)). Click **Publish**.
3. Make sure the `GLOW_REVIEW_*` and `GLOW_FEEDBACK_EMAIL` secrets exist (step 8).
4. GitHub → **Actions → Release iOS → Run workflow** → lane **external** (leave build empty for the latest) → Run. Or `ios/fastlane/ship external` on your Mac.

The lane fills in Test Information (description, feedback email, privacy policy) and the Beta App Review notes from `ios/fastlane/testflight/`, adds the build to **Public** and submits it for review. Check on it with lane **status**. Put the review status in B9's section of `HANDOFFS.md`; **that ticks the third box** until it's approved.

Later builds of the same version usually pass without a full review. Builds don't go to **Public** by themselves: `beta` only feeds internal testers, so people with the public link stay on a build you chose. Run **external** again to give them a new one.

### 11. Turn on the public link

Once the review is approved:

1. TestFlight → **Public** → **Public Link** → **Enable Public Link** → set a tester limit (for example 1,000) → Enable.
2. Copy the link (`https://testflight.apple.com/join/XXXXXXXX`).
3. Give it to B2's `/r/{slug}` page (people without Glow see it there; it's waiting on a server variable, see HANDOFFS), to B7 for the posters, and put it in B9's section of `HANDOFFS.md`. Lane **status** prints it too.

### 12. Check Associated Domains on a real iPhone

Once the web domain exists:

1. Set `GLOW_WEB_DOMAIN` in `ios/Glow/Config/Shared.xcconfig` (the only place the app reads it; it feeds `applinks:{DOMAIN}`, the links the app accepts and the Release API URL, D33). Ask A1, since A1 owns the file.
2. Point the domain at the Vercel production deploy (Vercel → Settings → Domains).
3. Check B2's link file: `curl -si https://{DOMAIN}/.well-known/apple-app-site-association` must answer `200`, `application/json`, no redirect, with `appIDs` `["{TEAM_ID}.com.davidxie.glow"]` and the component `/r/*`. Apple's copy, which phones actually read: `curl -s https://app-site-association.cdn-apple.com/a/v1/{DOMAIN}` (it can lag a few hours).
4. Ship a build (step 9) and install it from TestFlight. iOS fetches the file when the app installs, so delete and reinstall if you changed it.
5. Open the iPhone **Camera**, point it at a room poster's QR code, and tap the banner. Glow must open on the room (not Safari). Also try a room link pasted into Notes and long-pressed: "Open in Glow" should be there.

## Where the web domain goes

Two places, once it's chosen:

- **The app:** `GLOW_WEB_DOMAIN` in `ios/Glow/Config/Shared.xcconfig`. Everything in the app derives from it. The release lane refuses to ship while it's still the `.invalid` placeholder.
- **The server:** B2's `GET /.well-known/apple-app-site-association` route, which must list `{TEAM_ID}.com.davidxie.glow` for `/r/*`, and the Vercel project's domain. The team and bundle IDs are already server variables (`APNS_TEAM_ID`, `APNS_BUNDLE_ID`).

## App Privacy answers

App Store Connect → Glow → **App Privacy** → Get Started. These match `ios/Glow/PrivacyInfo.xcprivacy` (D43: it declares more, not less) and are kept as data in `ios/fastlane/app-privacy.json`. `ios/fastlane/ship check` (and CI) fails if the manifest and the answers drift apart; then run `ios/fastlane/ship privacy_answers`, update this table, and change the answers in App Store Connect. `ios/fastlane/ship privacy` uploads them for you instead of clicking (it signs in with your Apple ID and leaves them unpublished for you to review).

**Do you or your third-party partners collect data from this app?** Yes. **Is any data used for tracking?** No, for every type.

| App Store Connect data type | Why | Purposes | Linked to the person |
| --- | --- | --- | --- |
| Contact Info → Name | First name, shown to a match | App Functionality | Yes |
| Contact Info → Email Address | The 6-digit sign-in code | App Functionality | Yes |
| Sensitive Info | Gender and who you want to see | App Functionality | Yes |
| Location → Precise Location | One fix per room check. Only pass or fail is kept. | App Functionality | Yes |
| User Content → Photos or Videos | Profile photos, and outfit photos blurred on the phone | App Functionality | Yes |
| User Content → Other User Content | Chat messages and report details | App Functionality | Yes |
| Identifiers → User ID | The account ID | App Functionality | Yes |
| Usage Data → Product Interaction | Anonymous product analytics (PostHog, never identified) | Analytics | No |
| Diagnostics → Crash Data | Crash reports, scrubbed | App Functionality | No |
| Diagnostics → Performance Data | Performance with crash reports | App Functionality | No |
| Other Data → Other Data Types | Birthday, for the 18+ check | App Functionality | Yes |

Everything else: not collected.

## Beta test information

The texts Apple and testers see live in `ios/fastlane/testflight/`, and the lanes send them:

| File | Where it shows | Sent by |
| --- | --- | --- |
| `description.txt` | Test Information → Beta App Description | `external` |
| `what-to-test.txt` | What to Test, on every build (plus the build number and commit) | `beta` and `external` |
| `review-notes.txt` | Beta App Review Information → Review Notes (plus `GLOW_REVIEW_VIDEO_URL` if set) | `external` |

Sign-in for reviewers: none needed (Sign in with Apple or the email code works for anyone), so "Sign-in required" stays off. There's deliberately no reviewer back door around the location check (D49); the notes explain what a reviewer can see outside a venue, and a recording of the full loop helps. Contact details come from the `GLOW_REVIEW_*` secrets, never from git.

Export compliance is answered in the app: `ITSAppUsesNonExemptEncryption` is `false` (standard HTTPS only), so no build waits on the question.

## Privacy policy draft

Needed at `https://{DOMAIN}/privacy` for App Privacy and external testing. A draft in Glow's voice, to check before publishing (it isn't legal advice). It needs a page on the server (requested from A1 in HANDOFFS).

> **Glow privacy policy**
>
> Glow helps two people in the same room find out, privately, that they noticed each other. We collect as little as we can, keep it only as long as Glow needs it, and never sell it or use it for ads or tracking.
>
> **What we collect.** Your email address (to send your sign-in code) or your Sign in with Apple ID; your first name, birthday, gender, who you want to see and up to 3 profile photos; outfit photos when you check in to a room; your taps, matches and chat messages; reports and blocks you make; a push notification token for your iPhone.
>
> **Location.** When you join a room, Glow takes one precise location fix and our server checks whether you're inside the room's area. We keep only whether the check passed, for 24 hours. Your coordinates are never stored or logged.
>
> **Photos.** Any face in an outfit photo is blurred on your iPhone before it's uploaded. Outfit photos are shown only to people checked in to the same room, with a faint code that traces screenshots, and are deleted within minutes of your check-in ending. Profile photos are shown only to people you've matched with.
>
> **Who sees what.** Nobody sees your name or profile photos until you both tap each other. Nobody is ever told that you tapped them unless it's mutual. Blocking someone hides you from each other everywhere.
>
> **Service providers.** Supabase stores our data. Vercel runs our servers. Upstash counts requests to stop abuse. Anthropic's Claude checks photos and messages for faces, nudity and abuse. Apple delivers notifications and Sign in with Apple. PostHog receives anonymous usage events and Sentry receives crash reports; neither is linked to you, and neither gets your name, photos, location or messages.
>
> **Keeping and deleting.** Taps last 24 hours. Chat messages are deleted when either of you ends the match. A report keeps the reported person's last 20 messages for our review. Delete your account in Settings and everything about you is deleted.
>
> **Age.** Glow is only for people 18 and over.
>
> **Contact.** {CONTACT_EMAIL}

## How signing works

Release builds sign manually (D46): the archive is signed with the Apple Distribution certificate and the two App Store profiles, by name, from `ios/project.yml`'s Release settings. That's what makes the archive's `aps-environment` `production`, which TestFlight push needs. It needs no registered device, no Admin-role API key and no extra repository for certificates. Debug builds still sign automatically with the team from `Shared.xcconfig`, and Simulator and CI builds aren't signed.

## Crash reports (Sentry)

The Sentry iOS SDK is left out for now because it downloads 3.2 GB per checkout (D36). To turn on crash reports for TestFlight builds:

1. In `ios/project.yml` (A1), uncomment the package under `packages:`:

   ```yaml
   Sentry:
     url: https://github.com/getsentry/sentry-cocoa
     exactVersion: 9.31.0
   ```

   and add `- package: Sentry` to the `Glow` target's `dependencies`. `Glow/Analytics/LiveAnalytics.swift` switches the scrubbed adapter on by itself.
2. Commit the updated `ios/Package.resolved`.
3. Add the `SENTRY_DSN` secret (step 8). The release lane passes it into the build; it's empty, and Sentry off, otherwise.
4. Optionally upload dSYMs for readable stack traces: add `sentry_debug_files_upload` after `build_app` in the Fastfile with a `SENTRY_AUTH_TOKEN` secret.

## When something fails

| Symptom | Fix |
| --- | --- |
| The TestFlight job says "skipped: blocked, needs Apple Developer account" | Steps 1 to 8 |
| `Can't release yet:` and a list | Each line names the variable or file to fix and what unblocks it |
| `No profile for team ... matching 'Glow App Store'` | The profile names in step 5 must match exactly, and the secrets in step 8 must be current |
| `Provisioning profile doesn't include the aps-environment entitlement` | Push wasn't checked on the App ID when the profile was made. Edit the App ID (step 2), then regenerate both profiles (step 5) |
| `The bundle version must be higher than the previously uploaded version` | Two releases raced. Run it again: the next run reads the new latest number |
| The build never reaches testers | TestFlight → the build → check for a missing compliance or processing error. `Glow team` must have automatic distribution on |
| A QR code opens Safari, not Glow | Step 12: the link file, `GLOW_WEB_DOMAIN`, and a fresh install |
| A certificate or profile expired (yearly) | Steps 4, 5 and 8 again |
