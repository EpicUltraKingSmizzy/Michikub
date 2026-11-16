# Michikub

An ad-free number-tile game for 2 to 4 friends. Phones connect directly to each other over the internet (WebRTC), with no game server, no accounts and no cloud storage. It's built with Flutter for Android and iPhone.

> Version 0.1.0 is the first playable build. Design choices made along the way are listed in [DESIGN_QUESTIONS.md](DESIGN_QUESTIONS.md) for review.

![The table](docs/table.jpg)

## What's in it

- **Practice vs bots**: you against 1 to 3 computer players, each set to Easy, Medium or Hard.
- **Pass-and-play**: 2 to 4 people on one phone, with a "pass the phone to…" cover screen between turns.
- **Host a game / Join a game**: online play with a 6-character room code, or with copy-and-paste invite messages that need no matchmaking service at all.
- **House rules with saved presets**: first meld (Off or 3 to 50), starting hand (7 to 20), jokers (0 to 4: red, black, yellow, blue), turn timer (Off/30/60/120 s) and tiles drawn when passing (1 to 3).
- **The table**: a mahogany table, a crimson velvet rack (10 per row, sliding up for a second row), gold face-down tiles for opponents, flying draw and play animations, and large suit symbols.
- **Gestures**: drag anywhere. Long-press a rack tile to grab its run or group. Long-press a table set to move it. Double-tap to split a set. Tap a tile then tap a set to auto-place it. A Make space button and an invisible 27-space snap grid with automatic room-making.

Computer players are picked at random from a roster of 12 robots, each with a picture and a tagline (`lib/app/bot_roster.dart`, `assets/bots/`). Practice setup shows who you're up against, and long-pressing a robot's avatar at the table shows its tagline. They decide a turn instantly and then play it out one action at a time: 2 s per new set, 1 s per split or set move, and 0.5 s per single tile. They follow the turn timer like everyone else.

All play, solo modes included, goes through the same rules engine (`lib/engine/`): the host's phone validates every move.

## Testing it by yourself

1. **Practice vs bots**: Home → *Practice vs bots*, choose 1 to 3 bots and their difficulty, then *Start practice*.
2. **Pass-and-play**: Home → *Pass-and-play*, enter 2 to 4 names, then play both sides.
3. **Test tools**: Home → *Options & house rules* → *Test tools*. Switch them on to get:
   - **Fixed deal (seed)**: the same number deals the same tiles every time.
   - **Deal me a joker**: guarantees you a joker in your opening hand.
   - **Draw pile size**: Full, 20, 8, 2 or 0, to reach the empty-pile ending quickly.
   - **Turn timer override**: 10 or 20 s, to test timeouts.
   - **Test buttons in the game menu**: *Win now* (results screen), *Draw 5* (second rack row), *Give me a joker*, *Empty the pile*, and *Timer to 3 s*.
   - Tip: a starting hand of 20 (in house rules) shows the rack's second row right away.

   Test tools only apply to Practice and Pass-and-play, never to online games.

| Practice setup | Results | Pass-and-play |
|---|---|---|
| ![](docs/practice_setup.jpg) | ![](docs/results.jpg) | ![](docs/pass_and_play.jpg) |

## Install on Android

Download `Michikub-v0.1.0.apk` from the [Releases](../../releases) page onto the phone, open it and allow "install unknown apps" for your browser or file manager when asked. The APK is signed with a debug key, which is fine for sideloading. Before a Play Store release it needs a real upload key.

## iPhone

The same code builds for iOS. Getting it onto iPhones needs a **Mac with Xcode** and an **Apple Developer account** ($99/year) to distribute through **TestFlight**: `flutter build ipa`, then upload with Xcode or Transporter. Free installs straight from Xcode stop working after 7 days.

## Build it yourself

Requirements: Flutter stable (3.50+), Android SDK 35/36 with build-tools, and JDK 17.

```bash
flutter pub get
flutter test                 # rules engine, layout and bot tests
flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk
flutter build web            # handy for quick UI checks in a browser
```

On the web build, `?demo=practice&seed=7` (or `?demo=hotseat`) jumps straight into a seeded game, which is useful for screenshots.

## How online play works

- The host's phone runs the authoritative `GameHost`. Each guest receives only its own rack, plus the shared table and tile counts.
- Matchmaking uses the free public **PeerJS broker** (`0.peerjs.com`), which only passes connection details. After that the phones talk directly over a WebRTC data channel, using Google's public STUN servers.
- **Invite by message** skips the broker completely: the host copies an invite, the friend pastes it and sends back a reply.
- **Not yet tested phone to phone.** The broker handshake was checked from the build machine, but WebRTC can't open a connection in that sandbox, so the first real test is on your phones.
- Some strict networks (certain mobile carriers or workplace Wi-Fi) block direct connections. There is deliberately no relay (TURN) server, so test with your group early.

## Project layout

```
lib/engine/   pure Dart: tiles, melds, board layout, host, bots (unit tested)
lib/net/      PeerJS signalling, WebRTC links, online host/guest sessions
lib/app/      saved preferences, local sessions (practice / pass-and-play)
lib/ui/       screens and the game table
test/         engine tests
```
