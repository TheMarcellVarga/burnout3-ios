# Compiles windows-setup.iss into Burnout3_Takedown_Installer-setup-x86_64.exe on a Windows
# machine, with Inno Setup's command-line compiler (ISCC) in its PORTABLE mode: it is fetched
# from its release page by a pinned URL and sha256 and installed under -ToolsDir\innosetup
# with /PORTABLE=1 /CURRENTUSER, which writes no registry entry, no uninstaller and no Start
# menu entry. Nothing system-wide is installed.
#
#   powershell -ExecutionPolicy Bypass -File make-windows-setup.ps1 -Package <dir> [-Out <dir>]
#
# <dir> is the package folder make-windows-cross.sh makes (burnout3-installer.exe, payload\,
# licenses\, installer.ico): unzip its zip.
param(
    [Parameter(Mandatory = $true)][string]$Package,
    [string]$Out = (Get-Location).Path,
    [string]$ToolsDir = (Join-Path $env:USERPROFILE "bo3-tools"),
    [string]$Version = "0.1.0"
)
$ErrorActionPreference = "Stop"
$pin = @{
    Url    = "https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe"
    Sha256 = "9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732"
}
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$inno = Join-Path $ToolsDir "innosetup"
$iscc = Join-Path $inno "ISCC.exe"
if (-not (Test-Path $iscc)) {
    New-Item -ItemType Directory -Force $ToolsDir | Out-Null
    $dl = Join-Path $env:TEMP "innosetup-6.7.3.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $pin.Url -OutFile $dl
    $got = (Get-FileHash $dl -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $pin.Sha256) { Remove-Item $dl; throw "innosetup download has sha256 $got, expected $($pin.Sha256)" }
    Start-Process -Wait -FilePath $dl -ArgumentList "/PORTABLE=1", "/CURRENTUSER", "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=`"$inno`""
    Remove-Item $dl
}
if (-not (Test-Path $iscc)) { throw "ISCC.exe was not found in $inno" }
New-Item -ItemType Directory -Force $Out | Out-Null
& $iscc "/DPackage=$Package" "/DVersion=$Version" "/O$Out" (Join-Path $here "windows-setup.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with status $LASTEXITCODE" }
Write-Host "built: $(Join-Path $Out 'Burnout3_Takedown_Installer-setup-x86_64.exe')"
