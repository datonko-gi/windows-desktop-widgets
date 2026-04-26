Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Native {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const uint MOD_ALT = 0x1;
    public const uint MOD_CONTROL = 0x2;
    public const uint MOD_SHIFT = 0x4;
    public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    public const int DWMWCP_ROUND = 2;
}
"@

# HotkeyHook — subclasses the form's WndProc to catch WM_HOTKEY and raise a managed event.
Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;

public class HotkeyHook : NativeWindow {
    public event Action HotkeyPressed;
    public void Hook(IntPtr h) { AssignHandle(h); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) {
            if (HotkeyPressed != null) HotkeyPressed();
        }
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms"

# ===== Config (25% smaller than original 397x148) =====
$script:CELL       = 9
$script:GAP        = 2
$script:WEEKS      = 20
$script:TPAD       = 5
$script:RPAD       = 6
$script:BPAD       = 5
$script:SUM_GAP    = 5
$script:LABEL_GAP  = 3
$script:LABEL_H    = 9
$script:INIT_TOP    = 10
$script:INIT_RIGHT  = 169

# Round button on the left
$script:BTN_X      = 8
$script:BTN_D      = 54
$script:BTN_GAP    = 8
$script:LPAD       = $script:BTN_X + $script:BTN_D + $script:BTN_GAP

# "Goal: / English" label above button (2 lines)
$script:BTN_LBL_H  = 22

$script:FormW = $script:LPAD + $script:WEEKS * ($script:CELL + $script:GAP) - $script:GAP + $script:RPAD
$script:FormH = $script:TPAD + 7 * ($script:CELL + $script:GAP) - $script:GAP + $script:SUM_GAP + $script:CELL + $script:LABEL_GAP + $script:LABEL_H + $script:BPAD

# Button centered vertically in the space below the label
$script:BTN_Y = [int]($script:TPAD + $script:BTN_LBL_H + ($script:FormH - $script:TPAD - $script:BTN_LBL_H - $script:BTN_D - $script:BPAD) / 2)

$script:ColorBg     = [System.Drawing.Color]::FromArgb(235,235,235)
$script:ColorEmpty  = [System.Drawing.Color]::FromArgb(215,215,215)
$script:ColorDone   = [System.Drawing.Color]::FromArgb(95,95,95)
$script:ColorGreen  = [System.Drawing.Color]::FromArgb(90,200,90)
$script:ColorBorder = [System.Drawing.Color]::FromArgb(40,40,40)
$script:ColorLabel  = [System.Drawing.Color]::FromArgb(110,110,110)
$script:ColorBtn    = [System.Drawing.Color]::FromArgb(100,100,105)
$script:ColorFuture = [System.Drawing.Color]::FromArgb(228,228,228)

# ===== Data =====
$script:DataDir  = Join-Path $env:APPDATA "HabitWidget"
$script:DataFile = Join-Path $script:DataDir "data.json"
if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }

function Load-Data {
    if (-not (Test-Path $script:DataFile)) {
        return @{ days = @{}; posX = $null; posY = $null; goal = "English"; threshold = 4 }
    }
    try {
        $raw = Get-Content $script:DataFile -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $days = @{}
        if ($obj.days) {
            foreach ($p in $obj.days.PSObject.Properties) {
                $days[$p.Name] = [bool]$p.Value
            }
        }
        $px = $null; $py = $null
        if ($obj.PSObject.Properties.Name -contains 'posX') { $px = $obj.posX }
        if ($obj.PSObject.Properties.Name -contains 'posY') { $py = $obj.posY }
        $goal = "English"
        if ($obj.PSObject.Properties.Name -contains 'goal' -and $obj.goal) { $goal = [string]$obj.goal }
        $thr = 4
        if ($obj.PSObject.Properties.Name -contains 'threshold' -and $obj.threshold) {
            $t = [int]$obj.threshold
            if ($t -ge 1 -and $t -le 7) { $thr = $t }
        }
        return @{ days = $days; posX = $px; posY = $py; goal = $goal; threshold = $thr }
    } catch {
        return @{ days = @{}; posX = $null; posY = $null; goal = "English"; threshold = 4 }
    }
}

function Save-Data {
    $obj = [PSCustomObject]@{
        version   = 1
        days      = $script:Data.days
        posX      = $script:Data.posX
        posY      = $script:Data.posY
        goal      = $script:Data.goal
        threshold = $script:Data.threshold
    }
    try {
        $obj | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $script:DataFile -Encoding UTF8
    } catch {}
}

$script:Data = Load-Data

# ===== Time helpers (Pacific) =====
try {
    $script:PTZ = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
} catch {
    $script:PTZ = [System.TimeZoneInfo]::Local
}

function Get-PTNow {
    [System.TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, $script:PTZ)
}

function Get-MondayOf($d) {
    $dow = [int]$d.DayOfWeek
    $off = if ($dow -eq 0) { 6 } else { $dow - 1 }
    return $d.Date.AddDays(-$off)
}

function Format-DKey($d) { $d.ToString("yyyy-MM-dd") }

# ===== Form =====
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($script:FormW, $script:FormH)
$form.FormBorderStyle = "None"
$form.ShowInTaskbar = $false
$form.StartPosition = "Manual"
$form.BackColor = $script:ColorBg
$form.TopMost = $false
$form.Text = "HabitWidget"

$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($null -ne $script:Data.posX -and $null -ne $script:Data.posY) {
    $form.Location = New-Object System.Drawing.Point([int]$script:Data.posX, [int]$script:Data.posY)
} else {
    $defX = $scr.Right - $script:FormW - $script:INIT_RIGHT
    $defY = $scr.Top + $script:INIT_TOP
    $form.Location = New-Object System.Drawing.Point([int]$defX, [int]$defY)
}

# Panel (drawing surface)
$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Fill"
$panel.BackColor = $script:ColorBg
$form.Controls.Add($panel)

# Enable double buffering
$panelType = $panel.GetType()
$prop = $panelType.GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
$prop.SetValue($panel, $true, $null)

# ===== Drawing =====
$panel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $now           = Get-PTNow
    $today         = $now.Date
    $todayKey      = Format-DKey $today
    $currentMonday = Get-MondayOf $now
    $leftMonday    = $currentMonday.AddDays(-($script:WEEKS - 1) * 7)

    # weekly counts (only for past/present days)
    $weekCounts = @{}
    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        $cnt = 0
        for ($r = 0; $r -lt 7; $r++) {
            $d = $wkMon.AddDays($r)
            if ($d -gt $today) { continue }
            $k = Format-DKey $d
            if ($script:Data.days.ContainsKey($k) -and $script:Data.days[$k]) { $cnt++ }
        }
        $weekCounts[$c] = $cnt
    }

    $emptyBrush  = New-Object System.Drawing.SolidBrush($script:ColorEmpty)
    $doneBrush   = New-Object System.Drawing.SolidBrush($script:ColorDone)
    $greenBrush  = New-Object System.Drawing.SolidBrush($script:ColorGreen)
    $futureBrush = New-Object System.Drawing.SolidBrush($script:ColorFuture)
    $borderPen   = New-Object System.Drawing.Pen($script:ColorBorder, 1)

    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        for ($r = 0; $r -lt 7; $r++) {
            $d = $wkMon.AddDays($r)
            $x = $script:LPAD + $c * ($script:CELL + $script:GAP)
            $y = $script:TPAD + $r * ($script:CELL + $script:GAP)
            if ($d -gt $today) {
                $g.FillRectangle($futureBrush, $x, $y, $script:CELL, $script:CELL)
                continue
            }
            $k = Format-DKey $d
            $brush = $emptyBrush
            if ($script:Data.days.ContainsKey($k) -and $script:Data.days[$k]) { $brush = $doneBrush }
            $g.FillRectangle($brush, $x, $y, $script:CELL, $script:CELL)
            if ($k -eq $todayKey) {
                $g.DrawRectangle($borderPen, $x - 1, $y - 1, $script:CELL + 1, $script:CELL + 1)
            }
        }
    }

    # Summary row
    $summaryY = $script:TPAD + 7 * ($script:CELL + $script:GAP) - $script:GAP + $script:SUM_GAP
    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        if ($wkMon -gt $today) { continue }
        $x = $script:LPAD + $c * ($script:CELL + $script:GAP)
        $brush = $emptyBrush
        if ($weekCounts[$c] -ge [int]$script:Data.threshold) { $brush = $greenBrush }
        $g.FillRectangle($brush, $x, $summaryY, $script:CELL, $script:CELL)
    }

    # Month labels
    $labelY = $summaryY + $script:CELL + $script:LABEL_GAP
    $font = New-Object System.Drawing.Font("Segoe UI", 7)
    $labelBrush = New-Object System.Drawing.SolidBrush($script:ColorLabel)
    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        for ($r = 0; $r -lt 7; $r++) {
            $d = $wkMon.AddDays($r)
            if ($d.Day -eq 1) {
                $txt = $d.ToString("MMM", [System.Globalization.CultureInfo]::InvariantCulture)
                $x = $script:LPAD + $c * ($script:CELL + $script:GAP) - 2
                $g.DrawString($txt, $font, $labelBrush, [float]$x, [float]$labelY)
                break
            }
        }
    }

    # "Goal: English" label above button (two lines, left-aligned with small padding)
    $goalFont = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
    $goalBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 70, 75))
    $goalFmt = New-Object System.Drawing.StringFormat
    $goalFmt.Alignment = [System.Drawing.StringAlignment]::Near
    $goalFmt.LineAlignment = [System.Drawing.StringAlignment]::Near
    $goalAreaX = 6
    $goalAreaW = $script:BTN_X + $script:BTN_D - $goalAreaX
    $g.DrawString("Goal:", $goalFont, $goalBrush,
        (New-Object System.Drawing.RectangleF([float]$goalAreaX, [float]$script:TPAD, [float]$goalAreaW, 14)), $goalFmt)
    $g.DrawString([string]$script:Data.goal, $goalFont, $goalBrush,
        (New-Object System.Drawing.RectangleF([float]$goalAreaX, [float]($script:TPAD + 11), [float]$goalAreaW, 14)), $goalFmt)
    $goalFont.Dispose()
    $goalBrush.Dispose()

    # Realistic knob: soft shadow + 3D gradient body + top highlight + subtle rim
    # 1. Shadow layers (multiple translucent ellipses for soft blur look)
    for ($i = 3; $i -ge 1; $i--) {
        $a = 25 - ($i * 5)
        $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($a, 0, 0, 0))
        $g.FillEllipse($sh, ($script:BTN_X + $i - 1), ($script:BTN_Y + $i), $script:BTN_D, $script:BTN_D)
        $sh.Dispose()
    }

    # 2. Knob body with vertical gradient (light top → dark bottom)
    $bodyRect = New-Object System.Drawing.RectangleF(
        [float]$script:BTN_X, [float]$script:BTN_Y,
        [float]$script:BTN_D, [float]$script:BTN_D)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $bodyRect,
        [System.Drawing.Color]::FromArgb(210, 210, 215),
        [System.Drawing.Color]::FromArgb(105, 105, 112),
        90.0)
    $g.FillEllipse($grad, $script:BTN_X, $script:BTN_Y, $script:BTN_D, $script:BTN_D)
    $grad.Dispose()

    # 3. Dark rim (thin outline)
    $rimPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 0, 0, 0), 1.0)
    $g.DrawEllipse($rimPen, $script:BTN_X, $script:BTN_Y, $script:BTN_D, $script:BTN_D)
    $rimPen.Dispose()

    # 4. Top highlight (soft white ellipse)
    $hlW = $script:BTN_D * 0.62
    $hlH = $script:BTN_D * 0.28
    $hlX = $script:BTN_X + ($script:BTN_D - $hlW) / 2.0
    $hlY = $script:BTN_Y + $script:BTN_D * 0.09
    $hlRect = New-Object System.Drawing.RectangleF([float]$hlX, [float]$hlY, [float]$hlW, [float]$hlH)
    $hlGrad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $hlRect,
        [System.Drawing.Color]::FromArgb(160, 255, 255, 255),
        [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
        90.0)
    $g.FillEllipse($hlGrad, [float]$hlX, [float]$hlY, [float]$hlW, [float]$hlH)
    $hlGrad.Dispose()

    $emptyBrush.Dispose(); $doneBrush.Dispose(); $greenBrush.Dispose(); $futureBrush.Dispose()
    $borderPen.Dispose(); $font.Dispose(); $labelBrush.Dispose()
})

# ===== Click vs drag =====
$script:Drag = @{
    Down       = $false
    Dragging   = $false
    StartSX    = 0
    StartSY    = 0
    FormStartX = 0
    FormStartY = 0
    ClickX     = 0
    ClickY     = 0
}

function Is-InButton($x, $y) {
    $cx = $script:BTN_X + $script:BTN_D / 2.0
    $cy = $script:BTN_Y + $script:BTN_D / 2.0
    $dx = $x - $cx
    $dy = $y - $cy
    $r  = $script:BTN_D / 2.0
    return (($dx * $dx + $dy * $dy) -le ($r * $r))
}

function Try-MarkToday {
    $now = Get-PTNow
    $k = Format-DKey $now.Date
    if (-not $script:Data.days.ContainsKey($k) -or -not $script:Data.days[$k]) {
        $script:Data.days[$k] = $true
        Save-Data
        $panel.Invalidate()
    }
}

function Unmark-Today {
    $now = Get-PTNow
    $k = Format-DKey $now.Date
    if ($script:Data.days.ContainsKey($k)) {
        $script:Data.days.Remove($k)
        Save-Data
        $panel.Invalidate()
    }
}

$panel.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:Drag.Down = $true
    $script:Drag.Dragging = $false
    $pt = [System.Windows.Forms.Cursor]::Position
    $script:Drag.StartSX = $pt.X
    $script:Drag.StartSY = $pt.Y
    $script:Drag.FormStartX = $form.Location.X
    $script:Drag.FormStartY = $form.Location.Y
    $script:Drag.ClickX = $e.X
    $script:Drag.ClickY = $e.Y
})

$panel.Add_MouseMove({
    param($s, $e)
    if (-not $script:Drag.Down) { return }
    $pt = [System.Windows.Forms.Cursor]::Position
    $dx = $pt.X - $script:Drag.StartSX
    $dy = $pt.Y - $script:Drag.StartSY
    if (-not $script:Drag.Dragging) {
        if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 4) {
            $script:Drag.Dragging = $true
        }
    }
    if ($script:Drag.Dragging) {
        $nx = $script:Drag.FormStartX + $dx
        $ny = $script:Drag.FormStartY + $dy
        $form.Location = New-Object System.Drawing.Point([int]$nx, [int]$ny)
    }
})

$panel.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:Drag.Down) {
        if ($script:Drag.Dragging) {
            $script:Data.posX = $form.Location.X
            $script:Data.posY = $form.Location.Y
            Save-Data
        } elseif (Is-InButton $script:Drag.ClickX $script:Drag.ClickY) {
            Try-MarkToday
        }
    }
    $script:Drag.Down = $false
    $script:Drag.Dragging = $false
})

# ===== Timer (day/week rollover) =====
$script:LastTodayKey = Format-DKey ((Get-PTNow).Date)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({
    $nk = Format-DKey ((Get-PTNow).Date)
    if ($nk -ne $script:LastTodayKey) {
        $script:LastTodayKey = $nk
        $panel.Invalidate()
    }
})
$timer.Start()

# ===== Right-click context menu =====
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')

function Edit-Goal {
    $current = [string]$script:Data.goal
    $newGoal = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter your goal:", "Edit Goal", $current)
    if ($null -ne $newGoal -and $newGoal.Trim() -ne "" -and $newGoal -ne $current) {
        $script:Data.goal = $newGoal.Trim()
        Save-Data
        $panel.Invalidate()
    }
}

function Edit-Threshold {
    $current = [string]$script:Data.threshold
    $input = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Days per week to turn green (1-7):", "Weekly goal", $current)
    if ($null -eq $input) { return }
    $n = 0
    if ([int]::TryParse($input.Trim(), [ref]$n) -and $n -ge 1 -and $n -le 7) {
        $script:Data.threshold = $n
        Save-Data
        $panel.Invalidate()
    }
}

$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$script:MenuThresholdItem = $ctx.Items.Add("", $null, { Edit-Threshold })
[void]$ctx.Items.Add("Edit goal...", $null, { Edit-Goal })
[void]$ctx.Items.Add("Unmark today", $null, { Unmark-Today })
[void]$ctx.Items.Add("-")
[void]$ctx.Items.Add("Close widget", $null, { $form.Close() })
$ctx.add_Opening({
    $script:MenuThresholdItem.Text = "Weekly goal: $([int]$script:Data.threshold) days..."
})
$form.ContextMenuStrip = $ctx
$panel.ContextMenuStrip = $ctx

# ===== Pin below other windows =====
function Sink-ToBottom {
    [Native]::SetWindowPos($form.Handle, [Native]::HWND_BOTTOM, 0, 0, 0, 0,
        [Native]::SWP_NOMOVE -bor [Native]::SWP_NOSIZE -bor [Native]::SWP_NOACTIVATE) | Out-Null
}

$script:HotkeyId = 1
$script:Hook = $null

$form.Add_Shown({
    try {
        $h = $form.Handle
        $ex = [Native]::GetWindowLong($h, [Native]::GWL_EXSTYLE)
        [Native]::SetWindowLong($h, [Native]::GWL_EXSTYLE,
            $ex -bor [Native]::WS_EX_NOACTIVATE -bor [Native]::WS_EX_TOOLWINDOW) | Out-Null
        # Native Win11 rounded corners
        $pref = [Native]::DWMWCP_ROUND
        [Native]::DwmSetWindowAttribute($h, [Native]::DWMWA_WINDOW_CORNER_PREFERENCE, [ref]$pref, 4) | Out-Null
        Sink-ToBottom

        # Global hotkey Ctrl+Alt+Shift+O -> Try-MarkToday
        $script:Hook = New-Object HotkeyHook
        $script:Hook.Hook($h)
        $script:Hook.add_HotkeyPressed({ Try-MarkToday })
        $mods = [Native]::MOD_CONTROL -bor [Native]::MOD_ALT -bor [Native]::MOD_SHIFT
        $vkO = 0x4F
        [Native]::RegisterHotKey($h, $script:HotkeyId, $mods, $vkO) | Out-Null
    } catch {}
    $panel.Invalidate()
})

# Keep re-sinking every 3s so widget stays beneath other windows
$sinkTimer = New-Object System.Windows.Forms.Timer
$sinkTimer.Interval = 3000
$sinkTimer.Add_Tick({ Sink-ToBottom })
$sinkTimer.Start()

$form.Add_FormClosed({
    try { [Native]::UnregisterHotKey($form.Handle, $script:HotkeyId) | Out-Null } catch {}
    Save-Data
})

[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
