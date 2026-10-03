# Release build of StuntCopter.exe with its Win32 resources (the icon).
# SwiftPM can't compile .rc files, so this compiles StuntCopter.rc with the Windows
# SDK's rc.exe and hands the .res to the linker. Run from the repository root:
#   pwsh Support/Windows/build.ps1
# Prints the bin directory; in GitHub Actions also sets the step output `bin`.
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."

$rc = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\rc.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $rc) { throw "rc.exe not found: install the Windows 10/11 SDK" }

New-Item -ItemType Directory -Force "$root\build" | Out-Null
$res = "$root\build\StuntCopter.res"
Push-Location "$PSScriptRoot"   # rc resolves StuntCopter.ico next to the .rc
try {
    & $rc.FullName /nologo /fo $res StuntCopter.rc
    if ($LASTEXITCODE) { throw "rc.exe failed ($LASTEXITCODE)" }
} finally { Pop-Location }

Push-Location $root
try {
    swift build -c release -Xlinker $res
    if ($LASTEXITCODE) { throw "swift build failed ($LASTEXITCODE)" }
    $bin = (swift build -c release -Xlinker $res --show-bin-path).Trim()
} finally { Pop-Location }

# Check the icon made it into the exe: ExtractIconEx with index -1 counts icons.
Add-Type -Namespace Win32 -Name Shell32 -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern uint ExtractIconExW(string file, int index, IntPtr[] large, IntPtr[] small, uint count);
'@
$icons = [Win32.Shell32]::ExtractIconExW("$bin\StuntCopter.exe", -1, $null, $null, 0)
if ($icons -lt 1) { throw "StuntCopter.exe has no icon resource" }
Write-Host "StuntCopter.exe: $icons icon resource(s)"

if ($env:GITHUB_OUTPUT) { "bin=$bin" >> $env:GITHUB_OUTPUT }
$bin
