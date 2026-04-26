# Building Windows desktop widgets

Practical guide for writing widgets that live on the Windows 10/11 desktop
wallpaper layer. Every recommendation here is empirical: stuff that worked
when other approaches silently failed.

Reference implementation: [`examples/habit-widget/habit_widget.ps1`](../examples/habit-widget/habit_widget.ps1).
Skeleton to copy: [`lib/boilerplate.ps1`](../lib/boilerplate.ps1).

## When to use this approach

Any small Windows widget: habit trackers, counters, status indicators, volume
or mic knobs, custom clocks, system monitors, goal boards. The deliverable is
a small PowerShell script + VBS launcher + `install.bat` that the user
double-clicks once and forgets.

## The two things that look easy but aren't

These are the gotchas that took the longest to debug. Get them wrong and the
widget appears not to show at all.

### 1. Do NOT use `SetParent` to Progman/WorkerW on Win11

The classic Rainmeter-style "reparent to WorkerW via `0x052C`" trick is
unreliable on Windows 11: on many configs `SetParent` makes the form
`Visible=False` permanently and `ShowDialog` never actually renders anything.
Symptoms: the PowerShell process is running, `EnumWindows` finds the form
handle, but the user sees nothing.

**Use this instead.** Keep the form as a normal top-level window and push it
to the bottom of z-order:

```powershell
# In C# Add-Type block:
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int idx, int v);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
public const int GWL_EXSTYLE = -20;
public const int WS_EX_NOACTIVATE = 0x08000000;
public const int WS_EX_TOOLWINDOW = 0x00000080;
public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
public const uint SWP_NOMOVE=0x0002, SWP_NOSIZE=0x0001, SWP_NOACTIVATE=0x0010;

# In Add_Shown:
$h = $form.Handle
$ex = [Native]::GetWindowLong($h, -20)
[Native]::SetWindowLong($h, -20, $ex -bor 0x08000000 -bor 0x00000080) | Out-Null
[Native]::SetWindowPos($h, [Native]::HWND_BOTTOM, 0,0,0,0, 0x0002 -bor 0x0001 -bor 0x0010) | Out-Null

# And a 3s timer re-sinks it (because any window activation can bump z-order):
$sinkTimer = New-Object System.Windows.Forms.Timer
$sinkTimer.Interval = 3000
$sinkTimer.Add_Tick({ [Native]::SetWindowPos($form.Handle, [Native]::HWND_BOTTOM, 0,0,0,0, 0x0013) | Out-Null })
$sinkTimer.Start()
```

Why it works: `WS_EX_NOACTIVATE` prevents the form from ever becoming the
active window (so clicks don't steal focus from the user's real app),
`WS_EX_TOOLWINDOW` keeps it out of Alt-Tab and the taskbar, `HWND_BOTTOM` puts
it underneath everything else. The timer compensates for the fact that any
`SetForegroundWindow` call elsewhere can push siblings up.

### 2. `FindWindow("Progman", null)` can return 0 on Win11

If you actually need Progman's HWND for some reason, don't trust `FindWindow`.
Use `EnumWindows` + `GetClassName` and match "Progman" manually. But per
gotcha #1, you probably don't need Progman at all.

## Rounded corners (Win11 native)

Matches the look of other Win11 widgets. One DWM call after the handle exists:

```powershell
# In C# Add-Type:
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
public const int DWMWCP_ROUND = 2;

# In Add_Shown:
$v = 2
[Native]::DwmSetWindowAttribute($form.Handle, 33, [ref]$v, 4) | Out-Null
```

## File layout

Place the widget in `C:\Users\<user>\<WidgetName>\` with these files:

```
<WidgetName>/
├── widget.ps1        main script
├── Widget.vbs        silent launcher (no console flash)
├── Widget.bat        alt launcher for debugging (shows console)
├── install.bat       creates Startup shortcut + launches
├── uninstall.bat     removes Startup shortcut
└── README.md
```

State lives in `%APPDATA%\<WidgetName>\data.json` with shape
`{ version, days|values, posX, posY }`. Never put state in the widget folder
itself; that folder should be installable as read-only.

## Autostart pattern

`Widget.vbs`: silent launcher (no console window flash on boot):

```vbscript
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
selfPath = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & selfPath & "\widget.ps1""", 0, False
```

`install.bat`: creates a `.lnk` shortcut in the user's Startup folder:

```bat
@echo off
setlocal
set "HERE=%~dp0"
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\<WidgetName>.lnk"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-Object -ComObject WScript.Shell; $l = $s.CreateShortcut('%LNK%'); $l.TargetPath = '%HERE%Widget.vbs'; $l.WorkingDirectory = '%HERE%'; $l.Save()"
start "" "%HERE%Widget.vbs"
```

## The core WinForms skeleton

See [`lib/boilerplate.ps1`](../lib/boilerplate.ps1) for a complete,
copy-pasteable skeleton. Key elements:

- `FormBorderStyle = "None"`, `ShowInTaskbar = $false`, `TopMost = $false`
- Single `Panel` docked `Fill`, double-buffering enabled via reflection on the
  private `DoubleBuffered` property
- Custom `Paint` handler does all drawing (don't add individual controls per
  cell; draw with `Graphics`)
- Drag-vs-click distinction: on `MouseDown` record screen position + form
  position; on `MouseMove` with button held, if total movement > 4 px, switch
  to dragging; on `MouseUp` decide based on flag
- `Windows.Forms.Timer` at 30 s for day/time rollover; redraw only when the
  relevant value actually changed (don't repaint every tick)
- Right-click `ContextMenuStrip` with at minimum **"Close widget"** since the
  form is not in the taskbar, the user has no other way to close it

## Diagnostic workflow when the widget doesn't show

Don't guess. Work through this in order:

1. **Is the process alive?**
   `Get-CimInstance Win32_Process -Filter 'Name="powershell.exe"' | Where-Object { $_.CommandLine -like '*widget.ps1*' }`
   If not, there's a syntax error or an `Add-Type` compile failure. Run the
   script from a visible PowerShell console to see the error.
2. **Does the form exist?** Enumerate the process's windows via `EnumWindows`
   + `GetWindowThreadProcessId` matching the widget PID. Inspect class name,
   rect, `IsWindowVisible`, parent hwnd.
3. **Is `Visible = False` with `Parent = 0` after `ShowDialog`?** That's the
   signature of the `SetParent`-broke-rendering problem (see gotcha #1).
   Switch to `HWND_BOTTOM`.

[`lib/diagnose.ps1`](../lib/diagnose.ps1) is a ready-to-run window inspector.

## Time zones

If the widget is date-sensitive (habit tracker, streak counter), don't use
local time. The user may be in a different zone than where they set the goal.
Use:

```powershell
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
$now = [System.TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, $tz)
```

`"Pacific Standard Time"` automatically handles DST (becomes PDT in summer).
Pick a zone that matches where the user's day boundary should be.

## Iteration workflow

Widget work is highly interactive: you want to see each change. Don't batch
many edits and ship a big diff. Pattern:

1. Make the change in `widget.ps1`
2. Run a parse check from a helper `.ps1`:
   `[System.Management.Automation.Language.Parser]::ParseFile(<path>, [ref]$null, [ref]$errors)`
3. Kill the running process (`Stop-Process` on the matching `Win32_Process`
   by `CommandLine`)
4. Relaunch via the `.vbs` (`Start-Process -FilePath ...`)
5. Look at the result and iterate

The parse check catches ~80% of mistakes before you have to notice a blank
desktop. Pair it with the diagnostic workflow above when something still goes
wrong.

## Don't bother with these

- WinForms handle creation hooks (`HandleCreated` event): put setup in
  `Add_Shown` instead; by then the handle definitely exists and the form is
  in a consistent state.
- `$form.TopMost = $true` as a "temporary fix": if you want "behind all
  windows", topmost is the wrong answer; fix the real z-order problem.
- Registry-based autostart: a Startup folder `.lnk` is simpler, user-visible,
  and easy to uninstall.
- `Application.Run($form)` instead of `$form.ShowDialog()`: `ShowDialog`
  works fine with timers and keeps the script structure linear.
