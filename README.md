# Box & Found — iOS

A native SwiftUI client for the Box & Found storage-inventory app. It talks to
the **same Supabase project** as the web client at `boxandfound.net` and the
Android client in `BoxAndFoundAndroid`, so there is no third backend and no
third authorization model: row-level security in Postgres, scoped to household
membership, guards every table for all three clients.

This is a new *client*, not a new *system*. Where the Android port already made
a decision — the entitlement shape, the error taxonomy, the palette, the
`boxes.icon` contract — this one follows it rather than inventing a second
answer.

Status: **M2 — reading the inventory, green on CI.** Sign in with email,
Apple, Google or Facebook; the box list with search and a household switcher;
box detail. 78 passing tests, five of which talk to the real project. Nothing
writes yet.

---

## The constraint that shapes this repo

**It is authored on Windows, where Xcode does not exist.** Nothing here has
ever been compiled on the machine it was written on. That is not a temporary
inconvenience to work around later — it decides the layout:

- **The `.xcodeproj` is generated, not committed.** `project.yml` is the
  project definition, and XcodeGen rebuilds the real project on the runner.
  A committed `.pbxproj` would be unreadable and unmergeable from here.
- **CI is the compiler.** `.github/workflows/ios.yml` builds and tests on a
  `macos-26` runner on every push. Its log is the only feedback that Swift
  actually accepts what was written, so it is tuned for readable errors rather
  than for speed.
- **Nothing is verified until that workflow is green.** Treat any file here
  that predates a green run as a draft, however confident it looks.

What this setup still cannot do: run the app. Compiling and passing unit tests
says the types line up; it says nothing about whether a screen looks right or a
gesture works. That needs a simulator on a Mac, or TestFlight on a device.

### What CI costs

macOS runners bill at **10x the minute rate** of Linux. A private repo on the
GitHub Free plan gets 2,000 included minutes a month, which is **200 macOS
minutes** — roughly 25-40 runs of this workflow. Two consequences worth
respecting:

- Push a milestone, not a file. Batching work into one run is the difference
  between a month of loop and a week of it.
- If the repo is public, macOS minutes on standard runners are free, and none
  of the above applies.

## Requirements

| | |
|---|---|
| Xcode | 26.x (the `macos-26` runner default is 26.4.1) |
| iOS deployment target | 17.0 — `@Observable` and the Observation-based `.environment` need it |
| XcodeGen | 2.46.0 or newer, installed by CI with `brew install xcodegen` |
| supabase-swift | 2.55.1 (the v3 line is still in beta) |

## Setup

1. Copy the config template and fill it in:

   ```bash
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

   `SUPABASE_URL` and `SUPABASE_ANON_KEY` come from Supabase -> Project Settings
   -> API — the same values the web client's `.env` and the Android client's
   `secrets.properties` carry. The anon key is safe in a shipped client; RLS is
   what protects the data. `Secrets.xcconfig` is gitignored.

2. Allowlist the OAuth redirect in Supabase -> Authentication -> URL
   Configuration, alongside the Android one:

   ```
   net.boxandfound.ios://login-callback
   ```

   Needed before M1. Without it Apple and Google sign-in complete in the
   browser and then fail to hand the session back.

3. There is no step three on Windows. Push, and read the workflow.

On a Mac, `brew install xcodegen && xcodegen generate && open BoxAndFound.xcodeproj`.

## Verified

**Green on CI as of run 34473367956:** 78 tests in 13 suites, both targets
compiling under Xcode 26 in Swift 6 language mode.

**Against the live project.** Five of those tests talk to the real Supabase
project rather than a fixture, and they are the ones worth the wall-clock time:

- A deliberately failing sign-in comes back as `.invalidCredentials`. That one
  assertion proves the URL resolves, the anon key is accepted, errors arrive
  structured, and the GoTrue code still maps to the case `AuthView` renders —
  `AuthFailure.from` turns a `URLError` into `.network` before any message
  matching runs, so an unreachable server could not have produced this result.
- Every PostgREST query the app builds is accepted: the owned/joined households
  pair, rooms by household, boxes with `box_items` embedded, and one box by id.
  They run unauthenticated, so RLS answers all of them with nothing —
  emptiness is not the point. PostgREST rejects a projection it cannot parse
  with a 400, so a query that returns at all is one the server understood. This
  is what confirms `box_items` resolves as a relationship with all seven named
  columns present, and that `anon` holds select grants on all four tables.
- The `PGRST116` mapping was a guess when it was written, and the live "no
  rows" reply confirms it: a missing box reads as `.notFound`, not as a broken
  request.

**Against the source of truth rather than a compiler.** Every value in
`PaletteHex` was diffed against `css/style.css` in the web repo and matches.
The supabase-swift API this code calls was read out of the v2.55.1 sources
rather than recalled, which is why the first build's only error was in this
repo's own code.

**Still not verified, and not verifiable from here:** that the app *looks*
right. Nothing has rendered a screen. The presenters are tested by calling
intents and reading view state, so the logic behind every screen is pinned, but
layout, navigation, gestures, the search bar's real behaviour and whether the
Apple sheet appears at all are untouched. That needs a simulator on a Mac, or
TestFlight on a device.

**The failures worth remembering.** None of them was a mistake about Swift
itself: an SSH host key a non-interactive push could not accept, a `static let
Regex` that Swift 6 rejects as shared mutable state, this repo's own
configuration trap firing inside the test host, `UserDefaults` not being
`Sendable`, and typed throws quietly declining to narrow a `catch` binding. The
third is written up under Gotchas; the last is why every `catch` in the data
layer binds its failure type explicitly.

## Architecture

MVP, with the layers held apart by what each is allowed to import.

**Domain** — entities and rules. Imports `Foundation` and nothing else: no
Supabase, no SwiftUI. `AuthFailure`, `Credentials`, `Premium`, `AuthState`,
`SignedInUser`. This is the layer ported from Android, and the reason those
ports were line-for-line rather than reinterpreted.

**Data** — the only layer that knows Supabase exists. Repositories take domain
types in and hand domain types back; the SDK's error taxonomy is translated at
the boundary in `AuthFailure+Supabase`, and `OAuthProvider` learns its Supabase
spelling in an extension there rather than in the enum itself.

**Presentation** — one presenter per screen, one UI model per presenter, and a
view that draws it. See `Presenter.swift` for the contract.

### Why the presenter looks like this

Textbook MVP hands the presenter a `View` protocol and has it call
`render(state)`. SwiftUI views are structs, recreated on every change and never
worth holding a reference to, so that half inverts: the presenter publishes one
`viewState` and SwiftUI does the calling. What survives, and what makes this MVP
rather than MVVM, is that the view is passive — it owns no state, sends every
action back as an intent (`emailChanged(_:)`, not a two-way `$binding`), and
never sees a domain type. A whole screen's behaviour is then testable by calling
methods and reading `viewState`, which is what `AuthPresenterTests` does.

`viewState` is computed from private stored properties rather than stored
itself, so there is no second copy to keep in step; `@Observable` tracks the
properties the computation touches and redraws when they move.

### Two kinds of model

A **domain model** is what the system is: `SignedInUser`, and from M2 the
`Household`, `Room`, `Box` and `BoxItem` mirrors of the tables. No formatting,
no copy, no ordering for display.

A **UI model** is what a screen shows: `AuthViewState`, `RootViewState`, and
their nested `Notice` and `ProviderButton`. Strings already worded, flags
already decided, lists already ordered. By the time a failure reaches one it is
a sentence — which is why `AuthCopy` lives in the presentation layer and why no
view can accidentally render a GoTrue string.

The translation is the presenter's job, in both directions: `AuthViewState`
carries its own `ProviderButton.Kind` rather than the domain's `OAuthProvider`,
so a tap arrives as a UI concept and leaves as a domain one.

The boundary is *varying* content, not every string on screen. Static field
labels ("Email", "you@example.com") stay in the view, where static text
belongs. Anything a presenter can change lives in the UI model, where a test
can read it.

## Decisions already taken

**Follow Android's ports, don't redo them.** `AuthFailure`, `Credentials` and
`Premium` are line-for-line ports of the Kotlin, including the GoTrue error
tables, so one server error produces the same case on every client. The
divergences are written down where they happen — currently one: the network
branch, because `URLError` is caught structurally before message-matching ever
runs.

**State from the session, not from the event.** `SessionStore` narrows on
whether a session accompanied the auth change rather than switching on
`AuthChangeEvent`. The event list grows between SDK releases; `session != nil`
does not.

**No dependency-injection container.** Android needs Hilt because the framework
constructs view models for you. Here the composition root is
`BoxAndFoundApp`, and everything that needs the client takes it as an
initialiser parameter defaulting to `SupabaseProvider.shared` — which is what
lets tests pass their own without a container.

**Raw hex, not a colour asset catalogue.** A catalogue would be a fourth place
the palette lives and could not be diffed against the CSS in a test.

## Server-side work this port creates

None of it is Swift, and the app cannot ship without it:

1. **An APNs delivery path.** `send-push.js` uses `web-push` against VAPID
   endpoints and `push_subscriptions` stores `endpoint`/`p256dh`/`auth`, a
   shape APNs has no use for. This is the same hole the Android port opened for
   FCM — worth solving once, for both.
2. **StoreKit purchase verification.** An endpoint that verifies an App Store
   transaction and writes the same three `user_metadata` fields
   `lemon-webhook.js` writes today. Apple is stricter than Google here: the
   Lemon Squeezy redirect will not survive review for digital goods.
3. **`/.well-known/apple-app-site-association`** on `boxandfound.net`, the
   sibling of the `assetlinks.json` already there, so invite and box links open
   the app.
4. **Sign in with Apple is not optional.** Offering Google or Facebook sign-in
   without it is an App Store rejection. It is already configured in Supabase
   for Android, so this is a client-side job only.

## Milestones

Numbered to match the Android client, so "M3" means the same thing in both.

| | | Status |
|---|---|---|
| M0 | Foundations — config, session state, palette, the pure ports | **done** |
| M1 | Sign in — email/password, Apple, Google, Facebook | **done**, never run against a live server |
| M2 | Read the inventory — households, rooms, boxes, items, search | **done** |
| M3 | Edit — box/room CRUD, items, taken/returned, photo upload | next |
| M4 | Households and invites — Universal Links on `boxandfound.net` | |
| M5 | Notifications and nudges — APNs, realtime feed, 24h cooldown | |
| M6 | Premium — StoreKit 2, verification, gates | |
| M7 | Room map, view-only — Canvas over the saved JSON | |
| M8 | Account lifecycle and release — deletion modes, offline cache, App Store listing | |

## Gotchas worth knowing

- **`//` starts a comment in xcconfig, mid-value included.** A URL written
  literally silently becomes `https:`. `Config/Secrets.xcconfig.example`
  defines `SLASH = /` and builds the URL from it. Do not "tidy" that away.
- **Keep the project path free of `&` and spaces** — the same reason the
  Android repo is `BoxAndFoundAndroid`. This one is `BoxAndFoundIOS`.
- **`Generated/` and `*.xcodeproj/` are gitignored.** If a `.pbxproj` ever
  appears in a diff, XcodeGen has been bypassed.
- **Running the tests launches the app.** `@testable import` of an application
  module needs `TEST_HOST`, which means the test bundle loads inside a real
  `BoxAndFound` process on a booted simulator. Anything that traps during
  startup — a `preconditionFailure` on missing configuration, say — takes the
  whole test run down with "Early unexpected exit" and no test results. It also
  costs about six minutes a run. Moving the `Data` layer into its own framework
  target would fix both; that is the first thing to do at M2.
- **`SWIFT_VERSION: 6.0` means Swift 6 language mode, not just a compiler.** A
  `static let` of any non-`Sendable` type is a hard error there, which rules
  out the obvious way to hold a compiled `Regex`. Compute it instead of
  reaching for `nonisolated(unsafe)`.
- **Strict concurrency is set to `minimal` on purpose.** supabase-swift 2.x is
  not fully `Sendable`-audited; turning it up before the first green build
  would mix language-mode complaints in with real errors. Revisit at M2.

## Layout

```
project.yml                     the project definition; the .xcodeproj is generated from it
Config/Secrets.xcconfig.example the template for local credentials
Sources/BoxAndFound/
  App/BoxAndFoundApp.swift      composition root
  Config/AppConfig.swift        build-time config, read back out of Info.plist
  Domain/                       entities and rules; imports Foundation and nothing else
    Auth/                       AuthFailure and its GoTrue mapping, Credentials, OAuthProvider
    Premium/Premium.swift       entitlement, ported from the web checkPremium
    Session/Session.swift       AuthState and SignedInUser
  Data/                         the only layer that knows Supabase exists
    SupabaseProvider.swift      the one client
    Auth/                       AuthRepository, the SDK error mapping, the Apple nonce
    Session/SessionStore.swift  narrows the auth stream to AuthState
  Presentation/
    Presenter.swift             what a screen is here, and why it is not MVVM
    Auth/                       AuthPresenter, AuthViewState, AuthCopy, AuthView
    Root/                       RootPresenter, RootViewState, RootView
    Theme/Palette.swift         palette ported from the web client's CSS
Tests/BoxAndFoundTests/         Swift Testing suites for the domain and the presenters
.github/workflows/ios.yml       the compiler
```
