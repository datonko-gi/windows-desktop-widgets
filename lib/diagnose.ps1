# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File diagnose.ps1 <widget-script-name>
# Example: diagnose.ps1 habit_widget.ps1
#
# Finds the PowerShell process running the given widget script, enumerates
# all its top-level windows, and prints class/title/visible/rect/parent for
# each. Use when the widget process is running but you see nothing on screen.

param([Parameter(Mandatory=$true)][string]$ScriptName)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public delegate bool EWP(IntPtr hwnd, IntPtr lParam);

public static class I {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EWP lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

function Get-Cls($h) { $sb = New-Object System.Text.StringBuilder 128; [I]::GetClassName($h, $sb, 128) | Out-Null; $sb.ToString() }
function Get-Title($h) { $sb = New-Object System.Text.StringBuilder 256; [I]::GetWindowText($h, $sb, 256) | Out-Null; $sb.ToString() }

$target = Get-CimInstance Win32_Process -Filter 'Name="powershell.exe"' |
    Where-Object { $_.CommandLine -like ('*' + $ScriptName + '*') } |
    Select-Object -First 1

if (-not $target) {
    Write-Host "No PowerShell process running $ScriptName." -ForegroundColor Yellow
    Write-Host "Likely causes: syntax error, Add-Type compile failure, or the script exited."
    Write-Host "Run it from a visible console to see the error:"
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File <path>"
    exit 1
}

$targetPid = [uint32]$target.ProcessId
Write-Host "Widget PID: $targetPid" -ForegroundColor Green

$script:wins = @()
$cb = [EWP]{
    param($hwnd, $lp)
    $wpid = 0
    [I]::GetWindowThreadProcessId($hwnd, [ref]$wpid) | Out-Null
    if ($wpid -eq $targetPid) {
        $r = New-Object I+RECT
        [I]::GetWindowRect($hwnd, [ref]$r) | Out-Null
        $parent = [I]::GetParent($hwnd)
        $script:wins += [PSCustomObject]@{
            Hwnd      = $hwnd
            Class     = (Get-Cls $hwnd)
            Title     = (Get-Title $hwnd)
            Visible   = [I]::IsWindowVisible($hwnd)
            Parent    = $parent
            ParentCls = if ($parent -ne [IntPtr]::Zero) { Get-Cls $parent } else { "" }
            Rect      = ("{0},{1}-{2},{3} ({4}x{5})" -f $r.Left, $r.Top, $r.Right, $r.Bottom, ($r.Right - $r.Left), ($r.Bottom - $r.Top))
        }
    }
    return $true
}
[I]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:wins | Format-Table -AutoSize -Wrap

$mainForm = $script:wins | Where-Object { $_.Class -like 'WindowsForms*' } | Select-Object -First 1
if ($mainForm) {
    if (-not $mainForm.Visible) {
        Write-Host ""
        Write-Host "Main form exists but Visible=False - classic SetParent-broke-rendering signature." -ForegroundColor Yellow
        Write-Host "Fix: remove SetParent to Progman/WorkerW and switch to HWND_BOTTOM approach."
        Write-Host "See SKILL.md gotcha #1."
    } elseif ($mainForm.Rect -match '^0,0-0,0') {
        Write-Host ""
        Write-Host "Form is visible but has zero size - size/location set to 0." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Form looks OK. If you still can't see it, check: monitor bounds, window is underneath a maximized app (try Win+D), or form bg color matches wallpaper." -ForegroundColor Cyan
    }
}
