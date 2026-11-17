# TapHand: handoff

## What this is
TapHand is a standalone macOS menu bar app (Swift Package Manager, AppKit, macOS 14+). It's a take on the
tapping feature of other cursor tools: while it's on, a pointing hand follows the pointer and visibly "taps"
(it presses in, tilts and sends out a ripple) on each left or right click, so clicks read clearly in OBS screen recordings and demos.
Richard wanted his own build with the fewest permissions possible.
TapHand triggers **no** permission prompts, never reads the keyboard, makes no network calls, and doesn't capture the screen.
It's a personal utility, **not** part of the Converse codebase.

## Where things are
This folder holds everything. Permanent home: `~/Claude/TapHand` (git; moved from a scratch session folder 2026-11-15).
- `README.md`: build/run steps, menu reference, design, the permissions table, and the verification record. **Read it first.**
- `Sources/TapHand/`: app source (8 files; see the README's "Files" section).
- `Support/Info.plist`: bundle id `local.taphand`, `LSUIElement` (no Dock icon).
- `build.sh`: `swift build -c release`, then wraps the binary in `build/TapHand.app` and ad-hoc signs it.
- `docs/frames/`: offscreen renders of rest/pressed states (`TapHand --render-frames <dir>`).
- `tools/harness.swift`: live test harness (see below).
- Settings: `~/Library/Preferences/local.taphand.plist` (reset with `defaults delete local.taphand`).

## Build / run
```bash
./build.sh && open build/TapHand.app
```
Toolchain used: Xcode 27.2, Swift 6.4.2 (package in Swift 5.10 language mode), macOS 27.3.

## Key design decisions (with evidence)
- **Overlay:** one borderless, transparent, non-activating `NSPanel` per screen. Window settings: `ignoresMouseEvents`,
  assistive-tech-high level, `.canJoinAllSpaces + .fullScreenAuxiliary + .stationary`. The app runs as `.accessory`, so it never takes focus.
- **Pointer following:** each panel's `CADisplayLink` polls `NSEvent.mouseLocation`. That needs no permission and updates every display refresh.
- **Clicks:** global and local `NSEvent` monitors for left/right mouse down/up only. These monitors observe events and can't block them,
  so clicks always pass through. A minimum press duration makes ~5 ms tap-to-click clicks visible.
- **Hand art:** SF Symbol `hand.point.up.left` (white fill, black outline, `.light` weight). The fingertip pixel is detected at runtime
  and pinned to the pointer hotspot, and the animation scales and rotates around it.
- **System cursor:** visible by default (public API only; the arrow tip sits on the fingertip). The opt-in "Hide System Cursor (private API)"
  setting uses `CGSSetConnectionProperty(..., "SetsCursorInBackground")` + `CGDisplayHideCursor`, loaded with `dlsym`, and is isolated in
  `CursorHider.swift`. macOS shows the cursor again whenever another app activates, so TapHand hides it again on
  `NSWorkspace.didActivateApplicationNotification`. Before that fix, the hide didn't stick. It also tracks how many hides it issued
  and calls `CGDisplayShowCursor` the same number of times to undo them.
- **Presentation mode:** a second, nearly invisible (alpha 0.001) panel per screen accepts and swallows clicks, at level `mainMenu - 1`,
  so the menu bar and TapHand's own menu stay clickable. This avoids a `CGEventTap`, which would need Accessibility.
  Side effect: scrolling is swallowed too.

## Verified (live, single 4K display, scripted via tools/harness.swift)
- The hand follows a scripted pointer glide, with the fingertip under the arrow tip.
- Left click held: hand pressed with ripple. The target window got 2/2 clicks, including a 5 ms down/up click.
- Presentation mode: the hand taps, and the target window got **0/2** clicks.
- Hide System Cursor: the arrow is gone from captures and returns after the app is killed.
- No permission dialog appeared, and no networking frameworks are linked (`otool -L`).

## Themes (2026-11-15)
Theme menu + Size slider replaced Hand Size. See README "Themes" and "Credits".
Effects/themes verified offscreen via `--render-themes`. 2026-11-16: launched live with the Giraffe theme,
confirmed by screen crop that he follows the pointer with the tongue tip on the hotspot; Richard tried it and
approved ("kind of awesome"). Other themes and the Size slider still not exercised live by Claude.

## Installed (2026-11-16)
`tools/install.sh` → `/Applications/TapHand.app` + LaunchAgent `local.taphand` (opens at login). Re-run to update.

## Custom cursors (2026-11-16)
Any PNG/SVG/PDF (+ optional JSON sidecar) in `~/Library/Application Support/TapHand/Cursors/` loads at runtime as a
theme (`CustomCursors.swift`). Rule: only redistributable art goes in this repo.

## Not verified / open items
1. Multiple displays and display hot-plug (the code rebuilds panels on `didChangeScreenParametersNotification`).
2. Full-screen apps and Spaces switching (the collection behavior is set, but this wasn't exercised).
3. An actual OBS recording. Display capture should include the overlay, since its sharing type is the default.
4. Right-click live test: the harness only sends left clicks, so orange double rings were checked only in `docs/frames`.
5. Possible polish: ripples are faint in captures taken ~100 ms after a click (fill alpha 0.22, 0.42 s fade). Consider a stronger
   fill or a longer fade. Hand-drag behavior while the button is held hasn't been looked at.
6. Global mouse monitors needed no permission on macOS 27.3. If a future macOS gates them, clicks would stop animating
   while following would keep working.

## Test harness
`tools/harness.swift` opens its own "TapHand test target" window, moves the pointer and posts real clicks via `CGEvent`.
It takes `screencapture -C` crops and prints `downs_received=N`. Posting events needs the *running terminal/host* to have
Accessibility, which Claude's host already had. TapHand itself does not need it.
```bash
swiftc -O tools/harness.swift -o /tmp/harness && mkdir -p /tmp/shots && /tmp/harness /tmp/shots normal
```
It moves the real mouse for about 3 s and puts it back afterwards. Toggle modes with `defaults write local.taphand presentationMode -bool true`
(or `hideSystemCursor`, `intensity expressive`), then relaunch the app before running it.
