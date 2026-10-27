# setup-gui-shot.ps1: the real setup's wizard over an install, with a screenshot of every page.
#
#   powershell -ExecutionPolicy Bypass -File setup-gui-shot.ps1 -Dir <folder> -OldSetup <exe> -NewSetup <exe> -Out <folder for the pngs>
#
# It needs the desktop session (a window is drawn and a key is sent to it), so
# start it from a scheduled task with /IT, not from an ssh session. The real
# setups write the uninstall key and the Start menu shortcut (see
# setup-test.ps1 -Real); the existing key and shortcut are saved first and put
# back at the end. The old setup is installed silently into <folder>, the new
# one is run with its wizard: each page is photographed, Enter is sent
# (Next, Update) until the Finish page, which is photographed and then closed
# by ending the process (its "Start Takedawn" box is ticked and would start the
# game on the real profile). Then the uninstaller removes it all.
param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$OldSetup,
      [Parameter(Mandatory = $true)][string]$NewSetup, [Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; } }
"@
$null = [W]::SetProcessDPIAware()
$T = Join-Path (New-Item -ItemType Directory -Force $Dir).FullName "guitest"
if (Test-Path $T) { Remove-Item -Recurse -Force $T }
New-Item -ItemType Directory -Force $T, $Out | Out-Null
$app = Join-Path $T "Programs\Takedawn"
$uninstPs = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8C1E5B0A-64D3-4C7E-A1F2-0D9B7E53A6C4}_is1'
$lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Takedawn.lnk'
$regBak = Join-Path $T "key.reg"; $lnkBak = Join-Path $T "lnk.bak"
$hadKey = Test-Path $uninstPs; $hadLnk = Test-Path $lnk
if ($hadKey) { cmd /c "reg export `"$($uninstPs -replace '^HKCU:','HKCU')`" `"$regBak`" /y > nul 2>&1" }
if ($hadLnk) { Copy-Item $lnk $lnkBak }
function Restore() {
    if ($hadKey) { cmd /c "reg import `"$regBak`" > nul 2>&1" }
    if ($hadLnk -and -not (Test-Path $lnk)) { Copy-Item $lnkBak $lnk }
}
trap { Restore; "ERROR $_"; break }
function Shot([IntPtr]$h, [string]$name) {     # the whole screen: the wizard is somewhere on it
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
    $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $Out $name), [Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}
function Buttons([IntPtr]$h) {
    $el = [Windows.Automation.AutomationElement]::FromHandle($h)
    $c = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::Button)
    ($el.FindAll([Windows.Automation.TreeScope]::Descendants, $c) | ForEach-Object { $_.Current.Name }) -join "|"
}
$p = Start-Process $OldSetup @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=`"$app`"") -Wait -PassThru
"old setup exit $($p.ExitCode); DisplayVersion " + (Get-ItemProperty $uninstPs).DisplayVersion
$s = Start-Process $NewSetup @("/SP-", "/DIR=`"$app`"") -PassThru
$n = 0; $shown = $false; $t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 120) {
    Start-Sleep 3
    $s.Refresh()
    if ($s.HasExited) { "setup exited $($s.ExitCode)"; break }
    # the window belongs to the .tmp process the setup exe starts, not to the exe itself
    $w = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($NewSetup) + ".tmp") -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $w) { continue }
    $w.Refresh(); $h = $w.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { continue }
    $n++; $png = "page$n.png"; Shot $h $png
    $v = (Get-ItemProperty $uninstPs).DisplayVersion
    "step ${n}: title [$($w.MainWindowTitle)] DisplayVersion $v -> $png"
    if ($v -eq "0.1.1") { break }      # installed: the Finish page; Enter there would start the game
    $null = [W]::SetForegroundWindow($h); Start-Sleep 1
    [Windows.Forms.SendKeys]::SendWait("{ENTER}")
}
if (-not $s.HasExited) {
    Start-Sleep 1
    Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($NewSetup) + ".tmp") -ErrorAction SilentlyContinue | Stop-Process -Force
    Stop-Process -Id $s.Id -Force
}
Start-Sleep 2
"after the wizard: DisplayVersion " + (Get-ItemProperty $uninstPs).DisplayVersion + ", exe " + (Test-Path (Join-Path $app "Takedawn.exe")) + ", .prev " + (Test-Path "$app.prev")
$p = Start-Process (Join-Path $app "unins000.exe") @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") -Wait -PassThru
Start-Sleep 3
"uninstall exit $($p.ExitCode); key gone " + (-not (Test-Path $uninstPs)) + "; lnk gone " + (-not (Test-Path $lnk)) + "; folder gone " + (-not (Test-Path $app)) + "; .prev gone " + (-not (Test-Path "$app.prev"))
Restore
"restored: key $hadKey, lnk $hadLnk; DONE"
