# Repose

Break reminder for macOS that lives in your menu bar.

<a href="https://github.com/fikrikarim/repose/releases/latest">
  <img src="assets/download-button.svg" alt="Download for Mac">
</a>

<br><br>

<a href="https://github.com/fikrikarim/repose/releases/latest">
  <p><img src="assets/break-overlay.png" width="600" alt="Repose break screen"></p>
  <p><img src="assets/menu.png" width="300" alt="Repose menu"></p>
</a>

You set a work interval and a break duration. Repose counts down in the menu bar, and when it hits zero, your screen goes dark and tells you to look away. When the break's over, the cycle starts again.

The thing that makes it actually usable: it won't interrupt you during calls. Repose watches whether your camera or mic is active, and pauses itself until you're done. No calendar setup, nothing to configure. If you're on a Zoom call, it knows.

## What's in the menu

Click the timer in the menu bar and you get:

- Pause, resume, restart
- Work interval picker (1 min to 60 min)
- Break duration picker (10 sec to 5 min)
- Toggle for meeting detection
- Toggle for whether breaks are skippable
- Launch at login
- Check for updates

Everything is right there, no settings window.

## How the meeting detection actually works

Most apps do this by checking your calendar or looking at what apps are running. Both are kind of bad. Your calendar doesn't know about the impromptu call your manager just pulled you into, and "Zoom is open" doesn't mean you're in a meeting.

Repose asks the hardware instead. It uses CoreMediaIO to check if any camera is active, and CoreAudio for the microphone. If something is using your camera or mic right now, you're probably in a call, so it backs off. When the device goes idle, the timer picks back up.

This means it works with everything. Zoom, Meet, FaceTime, Teams, Slack huddles, whatever you end up using next year. No need to know about any of them.

## Build from source

```
git clone https://github.com/fikrikarim/repose.git
cd repose
brew install xcodegen
xcodegen generate
open Repose.xcodeproj
```

Needs Xcode 15+ and macOS 13+.

## License

MIT
