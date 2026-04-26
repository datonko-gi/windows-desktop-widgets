# Habit Widget

Desktop habit tracker for Windows — lives on the wallpaper layer behind all windows.

## Layout

- Grid: 20 columns × 7 rows. Each column = one week (Mon → Sun top to bottom).
- Rightmost column = current week. History scrolls left as weeks roll over. Data older than 20 weeks disappears.
- Bottom row = weekly summary. Turns green when that week has ≥ 4 marked days.
- Labels below = month names (MMM) under the week containing day 1 of that month.
- Today's cell has a dark border frame that moves at midnight Pacific.

## Interaction

- **Left-click a cell** → mark that day done (dark gray). Second click does nothing — no toggle.
- **Drag** (hold left button, move) → reposition widget. Position is saved.
- **Right-click** → context menu: open data folder, reset position, close.
- Future days (after today) are drawn faintly and cannot be clicked.

## Timezone & rollover

- All day / week math runs in **Pacific Time** (`Pacific Standard Time`, auto DST → PDT/PST).
- A 30 s timer notices day changes; the border and column rotation update right at midnight PT.

## Files

| file                  | purpose                                              |
| --------------------- | ---------------------------------------------------- |
| `habit_widget.ps1`    | main PowerShell + WinForms widget                    |
| `HabitWidget.vbs`     | silent launcher (no console window)                  |
| `HabitWidget.bat`     | alternative launcher (brief console flash)           |
| `install.bat`         | creates a shortcut in Startup and launches the widget |
| `uninstall.bat`       | removes the Startup shortcut                         |

Data: `%APPDATA%\HabitWidget\data.json`

```json
{
  "version": 1,
  "days":  { "2026-04-14": true, "2026-04-16": true },
  "posX":  1320,
  "posY":  20
}
```

## Install

1. Keep this folder wherever you like (e.g. `C:\Users\<you>\HabitWidget\`).
2. Double-click `install.bat`. It creates a shortcut in the Startup folder and launches the widget.
3. On next Windows login the widget starts automatically.

## Uninstall

Run `uninstall.bat`, then close the widget via its right-click menu (or reboot).

## How it stays below other windows

The widget is a normal borderless form with `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`
extended styles, and is pushed to the bottom of the z-order via `SetWindowPos(HWND_BOTTOM)`.
A 3-second timer re-sinks it to the bottom so it stays beneath any freshly activated
application window. The `NOACTIVATE` style prevents it from stealing focus when you
click on cells — clicks register but the widget never becomes the active window.

## Notes

- The widget is not in the taskbar or Alt-Tab — close it via right-click → "Close widget".
- PowerShell 5.1 (shipped with Windows 10/11) is sufficient. No extra install needed.
- Changing wallpaper or display resolution can recreate `WorkerW`; if the widget
  disappears, relaunch `HabitWidget.vbs`.
