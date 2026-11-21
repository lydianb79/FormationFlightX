<img src="Resources/AppIcon.png" width="128" alt="FormationFlightX icon">

# FormationFlightX

A formation flight trainer for RC flying wings on macOS, written in Swift and rendered with Metal. Up to five pilots fly together, on one network or over the internet, with no server. Created by Rock FPV.

![FormationFlightX splash screen](Resources/Splash.jpg)

The look is its own: an evening-sky theme, a menu down the left edge with the flying site in view, and its own icon and splash.

FormationFlightX is built on [FlightCore OSX](https://github.com/lydianb79/FlightCoreOSX): the flight physics, the eleven flying wings, the weather, the sound and the renderer come from there. The flying sites, the menu music, the look and everything about flying together are its own.

## Build and run

Requirements: macOS 13 or later, a Mac with Metal support, and Xcode 15 or later (or the Swift 5.9+ command-line toolchain).

```bash
./build_app.sh
```

```bash
open FormationFlightX.app
```

Run the app bundle rather than the bare binary when you want multiplayer: macOS only lets an app with the right entries in its `Info.plist` search the local network, and `build_app.sh` writes them. The first launch asks for permission to find devices on the local network; say yes, or allow it later under **System Settings ▸ Privacy & Security ▸ Local Network**.

## Flying together

There is no server, no account and no host. Every copy of the app announces itself on the local network with Bonjour and looks for the others; each pilot then sends their wing's position straight to the others over UDP, sixty times a second. Macs on the same Wi-Fi or cable network find each other by themselves, and so do Macs with Wi-Fi on but no shared network, over Apple's peer-to-peer Wi-Fi.

- **Five pilots at most.** Each copy flies with the first four others it meets and ignores any more.
- **Groups.** Pilots with the same group name (Options) fly together, so two formations can share one network. An empty group flies with anyone.
- **The host runs the session** (see below): where it flies, the weather and daylight, and when it starts and stops.
- **The lead calls the formation.** Formation and spacing are the lead's. Until someone claims the lead, the pilot whose copy has the lowest network number leads. Press **U** (or **Take the Lead**) to claim it; press it again to hand it back.
- **All copies need the same version.** This version's messages are not understood by earlier builds.
- **Mid-air collisions** end the flight for both wings. You are put back behind your slot a few seconds later.
- A pilot who opens a menu stops being shown to the others until they fly again.

### On the same network

Nothing to set up: Macs on the same Wi-Fi or cable network find each other by themselves, and so do Macs with Wi-Fi on but no shared network, over Apple's peer-to-peer Wi-Fi.

### Over the internet

One pilot hosts and the others connect to the host. There is still no server: the host's copy of the app passes each pilot's positions on to the others.

1. **The host** opens **Options** and switches on **Host a session**. It then shows **your public address**, for example `203.0.113.5:47800`, with a Copy button; the lobby shows it too. The app also asks the router to open UDP port 47800 (NAT-PMP, PCP or UPnP) and says whether it did.
2. **The others** type that address under **Or join a host** and press **Connect**. The panel says when the host is answering.

If the router does not open the port by itself, the panel says so, in amber under the address: forward UDP port 47800 to the host's Mac in the router's settings (the panel gives the Mac's address on your network). The public address shown is right either way, but nobody outside gets through until the port is open.

The public address comes from the router when it opens the port. Otherwise the app asks a public "what is my address" service (api.ipify.org, then checkip.amazonaws.com, then icanhazip.com); this happens only while hosting is on, and it is the one thing the app ever asks of anyone outside the formation. The address is shown in Options and the lobby, not on the flight screen, so it does not end up in a stream or a screenshot by accident. A host name works as well as a number. If the internet provider shares one public address between customers (carrier-grade NAT), that connection cannot host; let someone else host, or put the Macs on one virtual network (ZeroTier, Tailscale) and join the host's address there.

Who hosts has nothing to do with who leads: any pilot can take the lead. Pilots on the host's own network join in by themselves and fly with the online ones. Everyone's traffic to an online pilot goes by way of the host, so the host's connection sets the delay.

Anyone who knows the address can connect while hosting is on. Set a group name to keep strangers out of the formation, and switch hosting off afterwards; that also closes the port on the router.

## Aircraft

Forty-six aircraft. The flying wings come first, and the app opens on one.

**FPV aircraft you can buy**, modelled from their published span, flying weight and wing area. Power, propeller and drag are set so that the simulated aircraft stalls, cruises and tops out where the real one is reported to (speeds in km/h, as measured by `--flighttest` in still air):

| Aircraft | Category | Span | Weight | Stall | Half throttle | Flat out |
|---|---|---|---|---|---|---|
| Alight Flik Wing | Wings | 0.50 m | 235 g | 32 | 45 | 85 |
| HeeWing F-01 | Wings | 0.69 m | 500 g | 37 | 60 | 110 |
| AtomRC Dolphin | Wings | 0.85 m | 620 g | 36 | 54 | 101 |
| SonicModell AR Wing | Wings | 0.90 m | 620 g | 35 | 53 | 98 |
| TBS Chupito | Wings | 0.80 m | 650 g | 39 | 83 | 151 |
| TBS Mojito | Wings | 1.27 m | 1800 g | 59 | 91 | 185 |
| AtomRC Penguin | Trainers & Sport | 0.75 m | 680 g | 30 | 46 | 88 |
| HeeWing T1 Ranger | Trainers & Sport | 0.73 m | 480 g | 29 | 43 | 83 |
| HeeWing T2 Cruza | Trainers & Sport | 1.20 m | 1900 g | 38 | 52 | 100 |
| ZOHD Altus | Trainers & Sport | 0.98 m | 920 g | 32 | 46 | 88 |
| AtomRC Swordfish | Trainers & Sport | 1.20 m | 1150 g | 39 | 54 | 101 |
| ZOHD Drift | Gliders | 0.88 m | 265 g | 22 | 31 | 59 |

What these are and are not:

- The **figures** are the makers' and retailers': span, flying weight, wing area where given, motor size, and for the Chupito and Mojito the published stall, cruise and top speeds. Where sources disagree (the Dolphin's weight, the Flik's span) a middle value is used. For the others the speeds are what pilots usually report for aircraft of that size and power, not measurements of mine.
- The **shapes** are the simulator's generic ones in the right proportions and colours, not copies of the mouldings. V-tails (Altus, Swordfish) are drawn and flown as conventional tails of the same size; the forward sweep of the Chupito and Mojito is drawn as a nearly straight wing.
- The Mojito's top speed comes out at 185 km/h; the maker says "upwards of 200".
- Each is trimmed in pitch for a gentle cruise (37 to 60 km/h) and in roll against its propeller's torque, as you would on the first flights, so it flies straight with the sticks let go. On more than cruise power the overpowered wings climb, as the real ones do; hold a little down or use the pitch trim (− and =).
- None of them has a flight controller: no stabilisation, no return to home.

**The other categories** each have a few aircraft from FlightCore OSX: trainers, scale civil, warbirds, aerobatic, foam 3D, jets, gliders, two helicopters and three multirotors. Those that are not hand-launched start on the runway, one behind the other in formation order. The eleven original flying wings are still there.

**Computer partners** fly any fixed-wing aircraft, and hold formation with all forty-one of them to within about 3 m RMS in `--formtest`. For fast aircraft the computer lead flies a larger racetrack. There are no computer partners when you fly a helicopter or a multirotor.

## Flying sites

Eighteen sites, none of them from FlightCore OSX. The site browser filters by kind.

| Site | Kind | |
|---|---|---|
| Stadium Circuit | Race Tracks | Eight gates in a loop on a sports ground; all left turns, two gates raised |
| Forest Slalom | Race Tracks | Seven gates along a ride cut through tall forest |
| Canyon Run | Race Tracks | Seven gates down a winding canyon sixty metres deep, four high ones back along the rim |
| Pylon Park | Obstacles | A slalom of pylons, three walls with windows, an arch, a limbo bar, a tunnel, two hoops |
| Container Yard | Obstacles | Lanes between stacked containers, gaps to dart through, gantry cranes to fly under |
| Downtown | Cities | Towers up to 120 m on a grid of 24 m streets, walkways across the avenues |
| Harbour Town | Cities | Low streets, quay cranes, two ships, and a bridge with 26 m of air under the deck |
| Heather Downs | Fields | Open downland; the easy one |
| Rice Terraces | Fields | A level step on a terraced hillside |
| Outback Aerodrome | Airfields | 460 m of red dirt, hangars and a tower |
| Karst Valley | Mountains | A valley floor between limestone towers |
| Caldera | Mountains | The floor of a crater, ringed by its wall |
| Archipelago | Water | The largest of a scatter of islands in shallow sea |
| Coral Atoll | Water | A ring of coral sixty metres wide round a lagoon |
| Badlands | Desert | A flat among gullied clay hills |
| Oasis | Desert | Gravel plain, a green-ringed pool, palm groves |
| Frozen Lake | Winter | A strip on a kilometre of ice |
| Tundra | Winter | Snow-patched grass and black meltwater pools |

**Racing.** On a race track the next gate glows. Fly through the first gate to start the clock, then through the gates in order; a gate out of order does not count. Every lap's time is shown, your best is kept until the site changes, and when you fly with others each lap is announced in the chat. The host's **Start Session** puts everyone on the launch line at once, which makes it a race. Gate posts are solid.

**Hitting things.** Everything built on a site is solid: gate posts, pylons, walls, containers, cranes, buildings, bridges, ships. So are trees, as before. A wing that touches one is wrecked and starts again a few seconds later.

**The computer lead** flies its racetrack above whatever is built: 38 m on open sites, higher over the yard, the harbour and the city (140 m over Downtown).

## Sessions

Whenever pilots fly together, one of them is the **host**: the pilot who switched on **Host a session** in Options, or, if nobody did, the one whose copy has the lowest network number. The lobby shows who it is.

- **Start Session:** everyone is put at the launch point and flies. The host's own **Take off** does the same when no session is running.
- **Restart:** the same again, at any time: everyone back to the launch point.
- **Stop:** everyone comes back to the lobby and stays there until the next start.
- **Changing the session:** the host chooses the flying site, the weather and the daylight (Lobby ▸ Site and Weather, or the usual menus), with the session stopped or running. Changing the site while it runs restarts everyone at the new site.
- **Wings:** every pilot can change their wing while the session is stopped. While it runs, only the host can.

Other pilots cannot fly while the session is stopped; their **Take off** button waits for the host. A pilot who joins while a session is running goes straight into it. If the host leaves, the next pilot in line becomes host and the session carries on as it was.

Before joining a host, enter your **pilot name**: it is at the top of the lobby and in Options, and **Connect** stays off while it is empty.

For the first six seconds after a launch, wings pass through each other, so that five pilots starting side by side can sort themselves out.

## Lobby, chat and voice

The **Lobby** (main menu, the speech-bubble button in the top bar, or **Return** in flight) is where the pilots meet before and between flights.

- **Pilots:** everyone in the formation, with their number, whether they are in the lobby, in the menus or flying, and a waveform beside whoever is speaking.
- **Chat:** write to the other pilots. In flight, what the others write appears for ten seconds under the formation box, and the speech bubble fills in when there is something unread.
- **Session:** whether it is running, who hosts, and for the host the buttons to start, restart and stop it.
- **Voice:** off, push to talk, or open mic.
  - *Push to talk:* hold the button in the lobby, or your talk control. "ON AIR" shows in the formation box while you are sending.
    - Keyboard: **B** in flight, or any key you choose.
    - Gamepad: left shoulder button, or any of twelve buttons you choose; works in the lobby too.
    - USB transmitter or joystick: assign "Push to talk" to a switch or button.
    - All three are set in Controller Setup (⌘, or **Change…** in the lobby).
  - *Open mic:* sends whenever you speak. Wear headphones, or the others hear themselves through your speakers; there is no echo cancellation.
  - The slider sets how loud the others are.

Voice is off until you choose a mode; the first time, macOS asks for permission to use the microphone. Speech is coded with Opus at about 3 KB per second and travels the same way as everything else, so it works on a local network and through an online host alike. Chat lines are sent five times over half a second, because single messages can be lost on the way.

Opening the lobby holds your own wing, as every menu does; the others see you as "in the lobby". To talk while flying, use voice.

## Flying alone

While no other pilot is connected, two computer-flown wings fill the formation (turn them off with **G**). They fly the same wing as you, so everyone has the same speed range.

- By default the computer leads round a wide racetrack about 38 m above the field, and you fly number 2 with another computer wing as number 3.
- Press **U** to take the lead: both computer wings then hold their slots on you.
- **K** hands your own wing to the autopilot, which flies whatever part you have: the racetrack if you lead, your slot if you do not.

Measured over 150 seconds of racetrack with each of the eleven wings (`--formtest`), the computer wingmen hold their slots to between 0.6 m and 2.8 m RMS, turns included, both behind a computer lead and behind your own wing on its autopilot after a hand launch. None of them crashes. The computer lead turns wider the wider the formation is, so the wingman on the inside of a turn keeps flying speed.

## Holding your slot

- A **ring** in the air marks your slot: amber while you are off station, green when you are in it.
- **Formations** in the main menu holds the five shapes and the spacing; **Options** holds the rest: the pilots, your name and group, the network, hosting and joining.
- The **formation box** (top left) shows your number, the formation, every other wing's distance, and how far you are from your slot. The little scope beside it is a top view with your wing in the middle and the slot as a circle; the bar on its right is the height difference.
- **On station** counts the share of your flying time spent inside the slot. The lead sees how far each wingman is off their slot instead.
- **J** puts you in the air a little behind your slot at the lead's speed, so you can practise the last part of a join-up again and again. **Space** starts with a hand launch from the pilots' position.

Formations for up to five: vic, echelon right, echelon left, line astern, line abreast. In a vic and line abreast, numbers 2 and 4 fly on the lead's right and 3 and 5 on the left. Spacing: tight, normal or loose, which is 1.5, 2.5 or 5 wingspans of the lead's wing between neighbours.

## Keys

| Key | |
|---|---|
| ← → ↑ ↓ | Roll and pitch (↓ pulls up) |
| W S, X | Throttle up and down, throttle cut |
| Return | Lobby: chat and voice |
| B (hold) | Talk, with voice on push to talk (the key can be changed) |
| J | Join up behind your slot |
| U | Take the lead / hand it back |
| O, I | Next formation, next spacing (lead only) |
| E, G | Flaps, landing gear (aircraft that have them) |
| C | Camera: chase, onboard, pilot on the ground |
| Y | Smoke (the others see it too) |
| Space | Start again with a hand launch |
| Esc, Tab | Main menu, wing browser |

**H** in the app lists the rest. Gamepads and USB RC transmitters work as in FlightCore OSX (Controller Setup, ⌘,).

## What is in the source

| File | |
|---|---|
| `Net.swift` | Bonjour discovery, hosting and joining, UDP transport and the message types |
| `Voice.swift` | Microphone capture, Opus coding, playback of the other pilots |
| `Formation.swift` | Formation shapes and slots, smoothing of network pilots, the computer pilot |
| `Structures.swift` | Gates, walls, containers, city blocks: where they stand, what they look like, hitting them, lap timing |
| `World.swift` | The sites: their landscapes and ground colours (the `FormationFlightX` cases), on FlightCore's terrain code |
| `FormationGame.swift` | Roster, lead, slots, collisions, chat, what is sent and shown |
| everything else | FlightCore OSX, limited to flying wings and 3D sites |

Command-line checks: `--flighttest` flies every fixed-wing aircraft and reports stall, half-throttle and top speed, climb, glide, roll rate, the speed it is trimmed for and whether it flies on hands-off, with a verdict against the real figures for the twelve FPV aircraft (`--new` for those only); `--sitetest` checks on every site that the five launch lanes are clear, that each gate is open with a way in and out and is counted in order, and that the computer lead's racetrack clears the ground and everything built; `--voicetest` sends speech and chat through the coder and the message format with no audio hardware; `--formtest` flies the computer partners with every wing and prints how well they hold formation; `--formtrace <wing> <0|1>` prints one flight in detail; `--net --netlog --name <name>` runs a windowed copy that logs who it sees; add `--host`, or `--join <address>`, and `--nobonjour` to try the online path on one Mac.

## Not yet done

- The new aircraft were checked by the automated flight test, not flown by hand or compared against flight logs of the real ones.

- The new sites were checked by rendering each one and by `--sitetest`; none of the race tracks or obstacle courses has been flown by hand, so how hard they are is a guess.
- Computer wingmen do not steer round buildings, gate posts or trees. Behind a computer lead they stay above everything; behind you they follow where you go, and hit what is in the way.
- Buildings and containers do not disturb the wind.

- Tested with copies on one Mac only: local discovery with two copies, and a host with two joiners (local discovery switched off, so everything went by way of the host). Separate Macs, peer-to-peer Wi-Fi and a real internet path with its delay have not been tried, and the router on the test network did not open the port by itself, so the automatic port opening has only been seen to fail politely.
- The session controls and the five-pilot limit were tested with copies on one Mac: a host and one guest through start, stop, restart, a change of site and daylight, and the wing lock; and a host with five joiners, of whom each flew with four others. With more than five copies, who ignores whom is not coordinated.
- Push to talk on a gamepad or a USB transmitter could not be tried here: no controller was connected. The keyboard key and the setup window were built but only the logic was exercised.
- Voice has been tested without a microphone: a generated tone went through the coder, the network (direct and by way of the host) and the decoder and came out at the right level, and the players started. Capture from a real microphone, how it sounds, and the delay have not been checked by ear.
- No echo cancellation or noise suppression, and no per-pilot mute.
- Positions are predicted forward to cover network delay; this suits a local network, and has not been tuned for the 50 to 150 ms of an internet path.
- The other wings make no sound, cast no shadow on the ground beyond 14 m from yours, and do not break apart when they crash.
- No wake turbulence behind another wing.
- `main.swift` still carries FlightCore's test commands, several of which name aircraft that are no longer in the library.

## License

GPL-3.0, as FlightCore OSX. See `LICENSE`.
