# Builds the installer for Windows and assembles the folder windows-setup.iss
# wraps. Not run on Windows yet: the driver's Windows backend is still being
# written (docs/installer.md), so treat the payload part as the outline.
#
#   powershell -ExecutionPolicy Bypass -File make-windows.ps1 `
#       -Qt C:\Qt\6.8.0\msvc2022_64 [-Toolkit C:\src\xboxrecomp] [-Python C:\python-embed]
#   iscc /DPackage=<this folder>\package /DVersion=0.1.0 windows-setup.iss
#
# -Python is an extracted "embeddable package" of python.org (3.10 or newer) with
# capstone installed into it (pip install --target <dir>\Lib\site-packages capstone);
# neither is game-derived, so both may be shipped.
param(
    [Parameter(Mandatory = $true)][string]$Qt,
    [string]$Toolkit = "",
    [string]$Python = ""
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$gui = Split-Path -Parent $here
$repo = (git -C $gui rev-parse --show-toplevel).Trim()
$build = Join-Path $gui "build-windows"
$package = Join-Path $here "package"

cmake -S $gui -B $build -DCMAKE_BUILD_TYPE=Release "-DCMAKE_PREFIX_PATH=$Qt"
cmake --build $build --config Release
Remove-Item -Recurse -Force $package -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $package | Out-Null
$exe = Get-ChildItem -Recurse $build -Filter burnout3-installer.exe | Select-Object -First 1
Copy-Item $exe.FullName $package
& "$Qt\bin\windeployqt.exe" --release --no-translations (Join-Path $package "burnout3-installer.exe")

# The payload (LocateDriver looks for payload\burnout3\tools\install\install.py).
$payload = Join-Path $package "payload"
New-Item -ItemType Directory -Force "$payload\burnout3" | Out-Null
# Explicit lists, as in payload.sh (no docs/, backlog/, tests/, installer sources).
$include = "LICENSE","README.md","CMakeLists.txt","cmake","config","regen.sh","src","tools/install","tools/win"
git -C $repo archive HEAD $include | tar -x -C "$payload\burnout3" --exclude "tools/install/gui" --exclude "tools/install/tests"
(git -C $repo rev-parse HEAD) | Set-Content "$payload\STAMP"
$licenses = Join-Path $package "licenses"
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item "$repo\LICENSE" "$licenses\burnout3-LICENSE.txt"
Copy-Item "$gui\licenses\Qt-*.txt","$gui\licenses\README.txt" $licenses
if ($Toolkit) {
    New-Item -ItemType Directory -Force "$payload\xboxrecomp" | Out-Null
    $tk = "LICENSE","LICENSES","NOTICE","README.md","CMakeLists.txt","cmake","include","src","templates","tests","third_party","tools/__init__.py","tools/xbe_parser","tools/disasm","tools/func_id","tools/abi_analysis","tools/recomp"
    git -C $Toolkit archive HEAD $tk | tar -x -C "$payload\xboxrecomp"
    Copy-Item "$Toolkit\LICENSE" "$licenses\xboxrecomp-LICENSE.txt"; Copy-Item "$Toolkit\NOTICE" "$licenses\xboxrecomp-NOTICE.txt"
    Copy-Item "$Toolkit\LICENSES\LGPL-2.1.txt" "$licenses\xboxrecomp-LGPL-2.1.txt"
}
if ($Python) { Copy-Item -Recurse $Python "$payload\python" }   # PythonProgram() looks for payload\python\python.exe
if (Get-ChildItem -Recurse $payload -Include *.xbe, *.iso, *.xiso, *.png, *.jpg, *.gif, *.mp4, *.wav, *.ogg) { throw "the payload holds game files" }

# The window's own icon is drawn at run time; the exe has none. Write one for
# the Inno wrapper if wanted:  burnout3-installer.exe --write-icon installer.ico
Write-Host "package ready: $package"
