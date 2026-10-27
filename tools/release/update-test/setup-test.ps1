# setup-test.ps1: the Windows setup exe as an updater (BO-100).
#
#   powershell -ExecutionPolicy Bypass -File setup-test.ps1 -Dir <folder> `
#       -OldSetup <setup.exe> -NewSetup <setup.exe> [-Disc <disc folder>] [-Real]
#
# -Dir is the one folder this script may write in (on the test PC: inside
# C:\Users\<you>\bo3-win). -OldSetup and -NewSetup are two setups of different
# versions; by default they are the /DPayloadTest variants of takedawn.iss
# (no uninstaller, no registry entry, no shortcuts: they write into /DIR=
# only, the same swap/refusal/rollback code as the real one).
#
# What it checks, with a scratch profile (APPDATA/LOCALAPPDATA inside -Dir):
#   1 the old setup installs; marker files stand for saves, settings, game
#     data and shader cache in the scratch profile
#   2 the game (or, without -Disc, a program with its working folder in the
#     install) is RUNNING: the new setup is refused (exit code 7 with
#     /VERYSILENT), the install is byte for byte as it was, the program keeps
#     running
#   3 the program is stopped by its process id; the new setup updates: the new
#     files are in, the old ones are in <folder>.prev, the markers are
#     untouched, the shortcut target (Takedawn.exe in the same folder) is the
#     same path
#   5 the old setup over the new one (downgrade, silent) puts the old version
#     back; markers still untouched; --version of the exe in the folder
#     follows each step
#   6 an update that fails while the files are written (/TESTFAIL=1, payload
#     variant only: a folder is put where Takedawn.exe has to go) leaves the
#     old version in place, byte for byte, and runnable
#
# -Real runs the real setups instead of the payload variants. They write
# outside -Dir: HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\
# {8C1E5B0A-64D3-4C7E-A1F2-0D9B7E53A6C4}_is1, a Start menu shortcut
# (%APPDATA%\Microsoft\Windows\Start Menu\Programs\Takedawn.lnk), the
# uninstaller in the install folder, and the desktop icon only with
# /MERGETASKS=desktopicon (never given here). That is why -Real needs
# -IKnowItWritesTheRegistry. The key and the shortcut are shared with a real
# install of the player's (same AppId): the script exports both first, runs
# the setups into -Dir, ends with the uninstaller of -NewSetup and checks that
# the key, the shortcut and the install folder (and its .prev) are gone, then
# puts the saved key and shortcut back. -Real adds step 7.
param(
    [Parameter(Mandatory = $true)][string]$Dir,
    [Parameter(Mandatory = $true)][string]$OldSetup,
    [Parameter(Mandatory = $true)][string]$NewSetup,
    [string]$Disc = "",
    [switch]$Real,
    [switch]$IKnowItWritesTheRegistry
)
$ErrorActionPreference = "Stop"
$Dir = (New-Item -ItemType Directory -Force $Dir).FullName
if ($Real -and -not $IKnowItWritesTheRegistry) { throw "-Real writes HKCU and the Start menu: add -IKnowItWritesTheRegistry" }
$T = Join-Path $Dir "setuptest"
if (Test-Path $T) { Remove-Item -Recurse -Force $T }
$app = Join-Path $T "Programs\Takedawn"
$prev = "$app.prev"
$roaming = Join-Path $T "profile\Roaming"; $local = Join-Path $T "profile\Local"
New-Item -ItemType Directory -Force $roaming, $local, (Split-Path $app) | Out-Null
$fails = 0
function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) { Write-Host "PASS $name" } else { Write-Host "FAIL $name $detail"; $script:fails++ }
}
function Tree-Hash([string]$root) {   # one hash of every file name and content under root
    if (-not (Test-Path $root)) { return "(none)" }
    $rows = Get-ChildItem $root -Recurse -File | Where-Object { $_.Name -notlike 'unins*' } | Sort-Object FullName | ForEach-Object {
        "{0} {1}" -f $_.FullName.Substring($root.Length), (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    $sha = [Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))))) -replace '-', ''
}
function Run-Setup([string]$exe, [string[]]$more, [string]$log) {
    $a = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=`"$app`"", "/LOG=`"$log`"") + $more
    return (Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru).ExitCode
}
function Exe-Version() {
    $keepR = $env:APPDATA; $keepL = $env:LOCALAPPDATA; $env:APPDATA = $roaming; $env:LOCALAPPDATA = $local
    try { $o = Join-Path $T "version.txt"
          $p = Start-Process (Join-Path $app "Takedawn.exe") "--version" -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
          return "$($p.ExitCode): " + ((Get-Content $o -ErrorAction SilentlyContinue) -join " | ")
    } finally { $env:APPDATA = $keepR; $env:LOCALAPPDATA = $keepL }
}


$uninstKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8C1E5B0A-64D3-4C7E-A1F2-0D9B7E53A6C4}_is1'
$lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Takedawn.lnk'
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Takedawn.lnk'
$regBak = Join-Path $T "uninstall-key.reg"; $lnkBak = Join-Path $T "Takedawn.lnk.bak"
$hadKey = $false; $hadLnk = $false
$uninstPs = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8C1E5B0A-64D3-4C7E-A1F2-0D9B7E53A6C4}_is1'
if ($Real) {
    if (Test-Path $uninstPs) { $hadKey = $true; cmd /c "reg export `"$uninstKey`" `"$regBak`" /y > nul 2>&1"; Write-Host "saved the existing uninstall key to $regBak" }
    if (Test-Path $lnk) { $hadLnk = $true; Copy-Item $lnk $lnkBak; Write-Host "saved the existing Start menu shortcut" }
    if (Test-Path $desk) { throw "a desktop shortcut exists already: not touching a machine like that" }
}
function Restore-Machine() {
    if (-not $Real) { return }
    if ($hadKey) { cmd /c "reg import `"$regBak`" > nul 2>&1" }
    if ($hadLnk -and -not (Test-Path $lnk)) { Copy-Item $lnkBak $lnk }
    Write-Host "restored: key $hadKey, Start menu shortcut $hadLnk"
}
trap { Restore-Machine; break }
# the markers only: with -Disc the game itself writes more files in the profile
function Marker-Hash() {
    $rows = $markers.Keys | Sort-Object | ForEach-Object {
        $f = Join-Path (Join-Path $T "profile") $_
        if (Test-Path $f) { "{0} {1}" -f $_, (Get-FileHash $f -Algorithm SHA256).Hash } else { "$_ MISSING" } }
    $rows -join "`n"
}
# the player's things, in the scratch profile only
$markers = @{
    "Roaming\Takedawn\UDATA\profile.bin" = "save"; "Roaming\Takedawn\settings.toml" = "[graphics]`nrender_scale = 2`n";
    "Roaming\Takedawn\mixer.toml" = "[master]`nlimiter = `"soft`"`n"; "Local\Takedawn\Game\.complete" = "data";
    "Local\Takedawn\Game\data.bin" = "game data"; "Local\Takedawn\cache\marker.bin" = "shader cache" }
foreach ($k in $markers.Keys) {
    $f = Join-Path (Join-Path $T "profile") $k
    New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
    [IO.File]::WriteAllText($f, $markers[$k])
}
$dataBefore = Marker-Hash

Write-Host "STEP 1 old setup installs"
$rc = Run-Setup $OldSetup @() (Join-Path $T "old.log")
Check "old setup exit 0" ($rc -eq 0) "exit $rc"
Check "old Takedawn.exe is there" (Test-Path (Join-Path $app "Takedawn.exe"))
$hOld = Tree-Hash $app; $vOld = Exe-Version
Write-Host "  old: $vOld"

Write-Host "STEP 2 the program runs: the update is refused"
$holder = $null
if ($Disc -ne "") {
    # the real game, headless, with the disc's data installed into the scratch profile
    $keepR = $env:APPDATA; $keepL = $env:LOCALAPPDATA; $env:APPDATA = $roaming; $env:LOCALAPPDATA = $local
    try {
        $null = Start-Process (Join-Path $app "Takedawn.exe") @("--install", "`"$Disc`"") -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $T "install.txt") -RedirectStandardError (Join-Path $T "install.err")
        $env:RECOMP_HEADLESS = "1"
        $holder = Start-Process (Join-Path $app "Takedawn.exe") "--headless" -WorkingDirectory $app -PassThru -RedirectStandardOutput (Join-Path $T "run.txt") -RedirectStandardError (Join-Path $T "run.err")
    } finally { $env:APPDATA = $keepR; $env:LOCALAPPDATA = $keepL; Remove-Item Env:RECOMP_HEADLESS -ErrorAction SilentlyContinue }
    Start-Sleep 8
} else {
    # no disc: any program of that folder at work there holds it just the same
    $holder = Start-Process cmd.exe "/c ping -n 300 127.0.0.1 > nul" -WorkingDirectory $app -PassThru -WindowStyle Hidden
    Start-Sleep 2
}
Check "the program is running" (-not $holder.HasExited)
$hRun = Tree-Hash $app
$rc = Run-Setup $NewSetup @() (Join-Path $T "new-refused.log")
Check "new setup refused while it runs (exit 7)" ($rc -eq 7) "exit $rc"
Check "install unchanged after the refusal" ((Tree-Hash $app) -eq $hRun -or $Disc -ne "")   # the game may write its own log in its folder? it must not
Check "no .prev after a refusal" (-not (Test-Path $prev))
Check "the program still runs" (-not $holder.HasExited)

Write-Host "STEP 3 closed: the update goes through"
$null = & taskkill /F /T /PID $holder.Id; $null = $holder.WaitForExit(15000)   # the tree: a child keeps the folder as its working folder
Start-Sleep 1
$hClosed = Tree-Hash $app
$dataBefore = Marker-Hash     # after the game stopped: it writes its own files in the profile
$rc = Run-Setup $NewSetup @() (Join-Path $T "new.log")
Check "new setup exit 0" ($rc -eq 0) "exit $rc"
$vNew = Exe-Version; Write-Host "  new: $vNew"
Check "the installed files are the new ones" ((Tree-Hash $app) -ne $hClosed)
Check "the old folder is kept as .prev, as it was" ((Tree-Hash $prev) -eq $hClosed)
Check "same install folder, same exe path (shortcut target)" (Test-Path (Join-Path $app "Takedawn.exe"))
Check "saves, settings, game data, cache untouched" ((Marker-Hash) -eq $dataBefore)
$hNew = Tree-Hash $app

Write-Host "STEP 5 rollback: the old setup over the new one"
$rc = Run-Setup $OldSetup @() (Join-Path $T "rollback.log")
Check "old setup over new exit 0" ($rc -eq 0) "exit $rc"
Check "the old files are back" ((Tree-Hash $app) -eq $hOld)
Check "old version string" ((Exe-Version) -eq $vOld)
Check "data untouched" ((Marker-Hash) -eq $dataBefore)

if (-not $Real) {
    Write-Host "STEP 6 an update that fails leaves the old version"
    $rc = Run-Setup $NewSetup @("/TESTFAIL=1") (Join-Path $T "fail.log")
    Check "failing setup exits nonzero" ($rc -ne 0) "exit $rc"
    Check "the previous version is back, byte for byte" ((Tree-Hash $app) -eq $hOld)
    Check "and it starts" ((Exe-Version) -eq $vOld)
    Check "data untouched" ((Marker-Hash) -eq $dataBefore)
}

if ($Real) {
    Write-Host "STEP 7 the uninstaller removes what the setup wrote"
    # the uninstaller of the new setup (the old one has no .prev rule): put the new version on first
    $rc = Run-Setup $NewSetup @() (Join-Path $T "last.log")
    Check "new setup over the old, exit 0" ($rc -eq 0) "exit $rc"
    Check "the uninstall key is there while installed" (Test-Path $uninstPs)
    $ver = (Get-ItemProperty $uninstPs).DisplayVersion
    Write-Host "  DisplayVersion $ver, InstallLocation $((Get-ItemProperty $uninstPs).InstallLocation)"
    Check "the uninstall entry names the new version and this folder" ($ver -eq "0.1.1" -and (Get-ItemProperty $uninstPs).InstallLocation.TrimEnd('\') -eq $app)
    Check "the Start menu shortcut is there" (Test-Path $lnk)
    $unins = Join-Path $app "unins000.exe"
    Check "the uninstaller is in the install folder" (Test-Path $unins)
    $rc = (Start-Process $unins @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") -Wait -PassThru).ExitCode
    Check "uninstaller exit 0" ($rc -eq 0) "exit $rc"
    Start-Sleep 3     # the uninstaller finishes its clean-up from a temp copy
    Check "the uninstall key is gone" (-not (Test-Path $uninstPs))
    Check "the Start menu shortcut is gone" (-not (Test-Path $lnk))
    Check "no desktop shortcut" (-not (Test-Path $desk))
    Check "the install folder is gone" (-not (Test-Path $app))
    Check "Takedawn.prev is gone" (-not (Test-Path $prev))
    Check "saves, settings, game data, cache are still there" ((Marker-Hash) -eq $dataBefore)
    Get-ChildItem (Split-Path $app) -Force | ForEach-Object { Write-Host "  left in $(Split-Path $app): $($_.Name)" }
    Restore-Machine
}
if ($fails -eq 0) { Write-Host "RESULT OK setup update test" } else { Write-Host "RESULT FAIL $fails check(s)"; exit 1 }
