# Skeleton PowerShell + WinForms desktop widget.
# Copy this into widget.ps1, rename WidgetName, and replace the Paint
# handler + click/interaction logic with your widget-specific behavior.
#
# Provides out of the box:
#   - Borderless form below all other windows (WS_EX_NOACTIVATE + HWND_BOTTOM)
#   - Native Win11 rounded corners (DwmSetWindowAttribute)
#   - Drag-vs-click distinction with 4px movement threshold
#   - State persistence in %APPDATA%\<WidgetName>\data.json
#   - 30s timer for time rollover
#   - Right-click "Close widget" context menu

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

# ===== Config =====
$script:WidgetName = "YourWidget"
$script:FormW      = 300
$script:FormH      = 120
$script:INIT_TOP   = 20
$script:INIT_RIGHT = 200   # pixels from right edge of screen

# ===== Data =====
$script:DataDir  = Join-Path $env:APPDATA $script:WidgetName
$script:DataFile = Join-Path $script:DataDir "data.json"
if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }

function Load-Data {
    if (-not (Test-Path $script:DataFile)) {
        return @{ values = @{}; posX = $null; posY = $null }
    }
    try {
        $obj = Get-Content $script:DataFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $values = @{}
        if ($obj.values) {
            foreach ($p in $obj.values.PSObject.Properties) { $values[$p.Name] = $p.Value }
        }
        $px = $null; $py = $null
        if ($obj.PSObject.Properties.Name -contains 'posX') { $px = $obj.posX }
        if ($obj.PSObject.Properties.Name -contains 'posY') { $py = $obj.posY }
        return @{ values = $values; posX = $px; posY = $py }
    } catch {
        return @{ values = @{}; posX = $null; posY = $null }
    }
}

function Save-Data {
    $obj = [PSCustomObject]@{
        version = 1
        values  = $script:Data.values
        posX    = $script:Data.posX
        posY    = $script:Data.posY
    }
    try { $obj | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $script:DataFile -Encoding UTF8 } catch {}
}

$script:Data = Load-Data

# ===== Form =====
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($script:FormW, $script:FormH)
$form.FormBorderStyle = "None"
$form.ShowInTaskbar = $false
$form.StartPosition = "Manual"
$form.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$form.TopMost = $false
$form.Text = $script:WidgetName

$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($null -ne $script:Data.posX -and $null -ne $script:Data.posY) {
    $form.Location = New-Object System.Drawing.Point([int]$script:Data.posX, [int]$script:Data.posY)
} else {
    $form.Location = New-Object System.Drawing.Point(
        ($scr.Right - $script:FormW - $script:INIT_RIGHT),
        ($scr.Top + $script:INIT_TOP))
}

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Fill"
$panel.BackColor = $form.BackColor
$form.Controls.Add($panel)

# Double-buffering via reflection (not exposed as a public property)
$prop = $panel.GetType().GetProperty("DoubleBuffered",
    [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
$prop.SetValue($panel, $true, $null)

# ===== Drawing =====
$panel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # TODO: draw widget content here
    $font = New-Object System.Drawing.Font("Segoe UI", 10)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
    $g.DrawString("$($script:WidgetName) - edit Paint handler", $font, $brush, 10, 10)
    $font.Dispose(); $brush.Dispose()
})

# ===== Drag vs click =====
$script:Drag = @{ Down=$false; Dragging=$false; StartSX=0; StartSY=0; FormStartX=0; FormStartY=0; ClickX=0; ClickY=0 }

$panel.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:Drag.Down = $true
    $script:Drag.Dragging = $false
    $pt = [System.Windows.Forms.Cursor]::Position
    $script:Drag.StartSX = $pt.X; $script:Drag.StartSY = $pt.Y
    $script:Drag.FormStartX = $form.Location.X; $script:Drag.FormStartY = $form.Location.Y
    $script:Drag.ClickX = $e.X; $script:Drag.ClickY = $e.Y
})

$panel.Add_MouseMove({
    param($s, $e)
    if (-not $script:Drag.Down) { return }
    $pt = [System.Windows.Forms.Cursor]::Position
    $dx = $pt.X - $script:Drag.StartSX
    $dy = $pt.Y - $script:Drag.StartSY
    if (-not $script:Drag.Dragging -and ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 4)) {
        $script:Drag.Dragging = $true
    }
    if ($script:Drag.Dragging) {
        $form.Location = New-Object System.Drawing.Point(
            [int]($script:Drag.FormStartX + $dx),
            [int]($script:Drag.FormStartY + $dy))
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
        } else {
            # Plain click — dispatch to widget-specific handlers using $script:Drag.ClickX / ClickY
            # TODO: call your button hit-test and action
        }
    }
    $script:Drag.Down = $false
    $script:Drag.Dragging = $false
})

# ===== Context menu =====
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
[void]$ctx.Items.Add("Close widget", $null, { $form.Close() })
$form.ContextMenuStrip = $ctx
$panel.ContextMenuStrip = $ctx

# ===== Attach to desktop (below all windows) + Win11 rounded corners =====
function Sink-ToBottom {
    [Native]::SetWindowPos($form.Handle, [Native]::HWND_BOTTOM, 0,0,0,0,
        [Native]::SWP_NOMOVE -bor [Native]::SWP_NOSIZE -bor [Native]::SWP_NOACTIVATE) | Out-Null
}

$form.Add_Shown({
    try {
        $h = $form.Handle
        $ex = [Native]::GetWindowLong($h, [Native]::GWL_EXSTYLE)
        [Native]::SetWindowLong($h, [Native]::GWL_EXSTYLE,
            $ex -bor [Native]::WS_EX_NOACTIVATE -bor [Native]::WS_EX_TOOLWINDOW) | Out-Null
        $pref = [Native]::DWMWCP_ROUND
        [Native]::DwmSetWindowAttribute($h, [Native]::DWMWA_WINDOW_CORNER_PREFERENCE, [ref]$pref, 4) | Out-Null
        Sink-ToBottom
    } catch {}
    $panel.Invalidate()
})

$sinkTimer = New-Object System.Windows.Forms.Timer
$sinkTimer.Interval = 3000
$sinkTimer.Add_Tick({ Sink-ToBottom })
$sinkTimer.Start()

# ===== Rollover timer (repaint on day/minute change if needed) =====
$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 30000
$refreshTimer.Add_Tick({
    # TODO: check whether the displayed value changed; if so, Invalidate
    # $panel.Invalidate()
})
$refreshTimer.Start()

$form.Add_FormClosed({ Save-Data })

[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
