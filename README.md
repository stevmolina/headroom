# Headroom

A small macOS menu bar app that shows how much room you have left on your AI coding plans.

The menu bar shows one ring and one number: the limit closest to running out, across every provider. Click it for three short tabs: Limits, Today and Sessions.

<p>
  <img src="docs/proof/panel-light.png" width="280" alt="Limits tab, light mode">
  <img src="docs/proof/today-light.png" width="280" alt="Today tab, light mode">
  <img src="docs/proof/sessions-dark.png" width="280" alt="Sessions tab, dark mode">
</p>

<img src="docs/proof/pill-dark.png" width="330" alt="The menu bar pill: a red ring and 0%">

Project names in these screenshots are hidden with `HEADROOM_REDACT=1`.

## What it shows

- **Limits tab.** One block per provider and quota group (Claude, Codex, Antigravity's Gemini and Claude/GPT groups, Grok, Cursor, anything tokscale reports). Each limit has a thin bar, % left and when it resets. When your pace says a limit runs out before it resets, it says "Runs out in about 3h".
- **Today tab.** Total cost and tokens, the last seven days as small bars, today's top model, and below it **Now**: agent sessions that wrote a message in the last five minutes, with project, model, elapsed time and cost so far.
- **Sessions tab.** Today's sessions. Click one for tokens in, out and cache, cost, duration, model and project.

The pill is grey normally, amber under 20% left and red under 5% left. Choose which providers count toward the pill in the `…` menu.

<img src="docs/proof/session-light.png" width="300" alt="Session detail">

## How it works

Headroom does not read any provider itself. It runs [tokscale](https://github.com/junhoyeo/tokscale), a Rust CLI with accurate quota and session data, and draws its JSON:

| Section | Command | How often |
|---|---|---|
| Limits | `tokscale usage --json` | every 60 s and when the panel opens |
| Today | `tokscale graph --week` | every 3 min and when the panel opens |
| Now, Sessions | `tokscale sessions --json --today` | every 3 min and when the panel opens |

Every call runs off the main thread with a timeout. The last reading is saved to `~/Library/Application Support/Headroom/`, so the panel never goes blank: it shows "Updated 40s ago" instead. The forecast uses your recent pace when Headroom has seen a reading 15 to 90 minutes earlier, and the average pace since the window opened otherwise.

## Install

Requirements: macOS 14 or later, Xcode command line tools, and a tokscale build with the `sessions` command.

```bash
# 1. tokscale with `sessions --json` (until it ships upstream)
git clone https://github.com/stevmolina/tokscale && cd tokscale
git checkout integration/headroom
cargo build --release -p tokscale-cli
mkdir -p ~/.local/bin && cp target/release/tokscale ~/.local/bin/

# 2. Headroom
git clone https://github.com/stevmolina/headroom && cd headroom
scripts/bundle.sh          # builds Headroom.app, installs to /Applications and opens it
```

Headroom looks for tokscale in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and `~/.cargo/bin`, or at `$HEADROOM_TOKSCALE`.

On macOS 27 a new menu bar item can start in the overflow (the `«` button). With a menu bar manager such as [holzBar](https://github.com/holzcloud/holzBar), set Headroom to Visible. Keep the app in `/Applications` and signed with a developer identity (the script does both when you have one): on macOS 27 the managers hide an ad-hoc app in `~/Applications` even when it is set to stay visible.

## Develop

```bash
swift build        # debug build
swift test         # unit tests: date parsing, model names, burn-rate forecast
swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

Environment switches: `HEADROOM_REDACT=1` hides project names, `HEADROOM_APPEARANCE=light|dark` forces the app's look, `HEADROOM_AUTOMATION=1` lets a script open the panel and step through it with distributed notifications named `dev.stevmolina.headroom.automation` (`open`, `tab:today`, `tab:sessions`, `session:0`, `back`, `close`), without touching the mouse.

## License

MIT
