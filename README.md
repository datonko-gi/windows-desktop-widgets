# Windows Desktop Widgets

Build widgets that live on the Windows 10/11 desktop wallpaper layer. They sit
below all your application windows, auto-start on login, persist their state,
and never steal focus when you click them. PowerShell + WinForms only, no
extra dependencies, no admin install.

## Widgets

Ready-to-install widgets built with the same approach. Each one has its own repo with screenshots, a README and a ZIP under Releases.

<!-- widgets-table:start -->
| Widget | What it does | Repo |
|---|---|---|
| Volume Mic Widget | Microphone volume meter for the Windows desktop. | [datonko-gi/volume-mic-widget](https://github.com/datonko-gi/volume-mic-widget) |
| Habit Tracker Widget | Multi-goal habit tracker with a 20-week grid, weekly targets and per-goal color themes. | [datonko-gi/habit-tracker-widget](https://github.com/datonko-gi/habit-tracker-widget) |
| Claude Usage Widget | Shows your Claude Code 5-hour and weekly usage limits as bars with reset countdowns. | [datonko-gi/claude-usage-widget](https://github.com/datonko-gi/claude-usage-widget) |
| AudioTap | Call recorder for Zoom, Teams and Meet: two audio tracks, local faster-whisper transcript, desktop widget. | [datonko-gi/audiotap](https://github.com/datonko-gi/audiotap) |
<!-- widgets-table:end -->

## Why this exists

The classic Rainmeter-style "reparent to WorkerW" trick is unreliable on
Windows 11: on many configs it leaves the form stuck at `Visible = False` and
nothing renders. The widgets in this repo use a different approach that
actually works:

- Keep the form as a normal top-level window
- Set `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` extended styles
- Push to `HWND_BOTTOM` and re-sink every 3 seconds

Result: the widget sits behind every other window, doesn't show in the taskbar
or Alt-Tab, and clicks register without ever activating the widget.

## Repo layout

```
docs/BUILDING_WIDGETS.md   full guide: z-order, rounded corners,
                           drag-vs-click, autostart, time zones, diagnostics
lib/boilerplate.ps1        copy-pasteable widget skeleton
lib/diagnose.ps1           window inspector for when a widget won't render
examples/habit-widget/     full habit tracker (20-week scrolling grid)
```

Companion repo (microphone volume meter):
[datonko-gi/volume-mic-widget](https://github.com/datonko-gi/volume-mic-widget).

## Quick start

Install the example habit widget:

```powershell
git clone https://github.com/datonko-gi/windows-desktop-widgets.git
cd windows-desktop-widgets\examples\habit-widget
.\install.bat
```

`install.bat` creates a shortcut in your Startup folder and launches the
widget. It appears at the bottom-right of the primary screen. Drag it where
you want; that position is saved to `%APPDATA%\HabitWidget\data.json`.

Right-click any widget in this repo to get a context menu (this is how you
close it; widgets are not in the taskbar or Alt-Tab).

## Build your own

1. Read [docs/BUILDING_WIDGETS.md](docs/BUILDING_WIDGETS.md). Pay particular
   attention to the **gotchas** section: those are empirical, not theoretical.
2. Copy [lib/boilerplate.ps1](lib/boilerplate.ps1) to `your_widget.ps1`.
3. Replace the `Paint` handler and click logic with your widget-specific
   behavior. Keep the form-creation, z-order, and persistence code as is.
4. Copy `examples/habit-widget/{install.bat, *.vbs}` and rename `HabitWidget`
   to your widget name throughout.

If your widget doesn't render, run `lib/diagnose.ps1` and check the form's
class name, rect, visibility, and parent hwnd. The diagnostic workflow in the
guide walks through what each result means.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built-in, no install)
- No .NET install, no admin rights

## License

MIT. See [LICENSE](LICENSE).
