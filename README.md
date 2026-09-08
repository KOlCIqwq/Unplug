<p align="center">
  <img src="assets/logo.png" alt="Unplug logo" width="128" />
</p>

# Unplug

Unplug is an Android screen-time and habit intervention app built with Flutter.

Instead of hard-locking your phone behind passwords you end up removing, Unplug introduces a brief pause whenever you open distracting apps. A short breathing timer gives you a moment to reconsider. From there, you can either step away or give yourself a finite, intentional session.

## Core features

- Pause screens with a breathing timer and reflection prompts when opening blocked apps
- Temporary unlock windows (such as 5 or 15 minutes) that re-lock when time expires
- Daily usage limits per app to cap extended scrolling
- Zen mode to silence notifications and restrict phone usage to essential tools
- Resisted urge counters that calculate time saved using your average session length
- Focus task logs to assign reclaimed minutes toward specific projects or study goals
- In-app alarms with full-screen ring notifications
- Home screen widget for quick Zen mode toggles

## How it works

Unplug pairs Flutter with a native Android Accessibility Service (`AppBlockerService`):

1. The background service detects when a package on your blocklist moves to the foreground.
2. If the app does not have an active temporary pass, the service opens the Flutter intervention view through a platform channel.
3. If you decide to exit, the app routes you back to the home screen and records the resisted urge.
4. If you choose a timed pass, the native service temporarily allows the package until the duration expires.

All statistics and configurations remain stored locally on your device through `SharedPreferences`.

## Android permissions

The app relies on several Android system permissions to operate:

- Accessibility Service: Detects when configured apps open in the foreground.
- Usage Stats: Measures screen time and monitors daily app limits.
- Exact Alarms and Full Screen Intent: Schedules alarms and displays alarm screens over other apps.
- Do Not Disturb: Allows Zen mode to mute notifications during active focus intervals.

## Getting started

### Prerequisites

- Flutter SDK (3.8 or newer)
- Android SDK (API 24+)
- A physical Android device (recommended for testing accessibility services) or an emulator

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/ToX.git
   cd ToX
   ```
2. Fetch Flutter packages:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```
4. Enable the Accessibility Service and Usage Access permissions in the app settings so Unplug can monitor foreground apps.
