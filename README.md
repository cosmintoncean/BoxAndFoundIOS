# Box & Found for iOS

A native iOS app for keeping track of everything you store, wherever you store
it.

Box & Found helps households organise physical belongings, track storage
locations, and keep an inventory of what is inside every box.

This repository contains the native SwiftUI application, built to work
alongside the existing Box & Found web and Android applications through a
shared backend. It is a new *client*, not a new *system*: all three apps read
and write the same Postgres tables under the same row-level security, so a box
packed on a phone is the same box in a browser.

## Features

- **Household inventory** — organise boxes, rooms and belongings.
- **Nested storage** — a room holds wardrobes, shelves and drawers; those hold
  boxes, and boxes hold things. Anything can also sit loose in a room or a
  container, the way a bike leans against a garage wall.
- **Search** — find stored items without opening every box.
- **Tags** — label boxes and items, and narrow the list to one label.
- **Item tracking** — keep track of items borrowed or temporarily taken out.
- **Room maps** — see where a box physically sits in a room, drawn from the
  plan made on the web.
- **Photos** — attach pictures to boxes and their contents.
- **Households** — share an inventory with other household members.
- **Invitations** — join households using invitation codes.
- **Notifications** — updates and reminders about shared items, including
  asking someone for something back.
- **Authentication** — email and password, Sign in with Apple, Google and
  Facebook, with password reset.

## Project status

The application is under active development.

| Area | Status |
| --- | --- |
| Authentication | Complete |
| Inventory and search | Complete |
| Box and item management | Complete |
| Nested storage and containers | Complete |
| Room maps | Complete, viewing only |
| Household sharing and invitations | Complete |
| Notifications and reminders | Complete, in the app |
| Tags | Filtering complete, editing pending |
| Push notifications | Pending — needs an Apple Developer Program account |
| Premium subscriptions | Pending — needs an Apple Developer Program account |
| Offline cache and account deletion | Planned |
| App Store release | Planned |

## Technology

- Swift 6
- SwiftUI
- iOS 17+
- Supabase — authentication, Postgres, storage and realtime
- XcodeGen
- Swift Testing, and XCTest for the UI suite

The iOS application shares its backend with the Box & Found web and Android
clients.

## Development

The project uses XcodeGen to generate its Xcode project from `project.yml`, so
the `.xcodeproj` is never committed. GitHub Actions builds and tests the app on
macOS runners; the suite is currently 286 unit tests and 26 UI tests that drive
the real screens in a simulator.

Every run also uploads a gallery: a screenshot of each screen in both light and
dark appearance, plus a recording of the test run. `DEVELOPMENT.md` explains
why that matters here, along with the architecture and the decisions behind it.

Building it yourself needs a Mac with Xcode 26, `xcodegen`, and a
`Config/Secrets.xcconfig` holding a Supabase URL and anon key — see
`Config/Secrets.xcconfig.example`.

## Links

- [Box & Found](https://boxandfound.net)
- [Android application](https://github.com/cosmintoncean/BoxAndFoundAndroid)
