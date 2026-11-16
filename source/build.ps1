# Construit GameBoost.exe (l'application) et GameBoost-Setup.exe (l'installateur) dans le dossier dist\.
# Rien a installer : le compilateur C# utilise est celui fourni avec Windows (.NET Framework 4).
#   .\build.ps1          construction normale
#   .\build.ps1 -Test    construit en plus les versions d'essai (sans droits administrateur) dans dist\test
param([switch]$Test, [string]$OutDir = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw "Compilateur C# introuvable (.NET Framework 4, inclus dans Windows 10 et 11)." }
$sma = [System.Management.Automation.PSObject].Assembly.Location    # moteur PowerShell de Windows, heberge par GameBoost.exe
$third = Join-Path $src 'third_party\PresentMon'
$L = Join-Path $src 'launcher'; $I = Join-Path $src 'installer'
New-Item -ItemType Directory -Force $OutDir | Out-Null

# Le script doit etre valide avant d'etre integre
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'GameBoost.ps1'), [ref]$null, [ref]$errs)
if ($errs.Count) { throw ("GameBoost.ps1 : " + $errs.Count + " erreur(s) de syntaxe, ligne " + $errs[0].Extent.StartLineNumber + " : " + $errs[0].Message) }

if (-not (Test-Path (Join-Path $L 'GameBoost.ico'))) { & (Join-Path $L 'make-icon.ps1') | Out-Null }

function Invoke-Csc([string[]]$a) {
    & $csc @a
    if ($LASTEXITCODE -ne 0) { throw "La compilation a echoue." }
}
function Build-App([string]$out, [string[]]$extra) {
    Invoke-Csc (@('/nologo', '/target:winexe', '/optimize+', "/out:$out", "/win32manifest:$L\app.manifest", "/win32icon:$L\GameBoost.ico",
        '/r:System.Windows.Forms.dll', '/r:Microsoft.CSharp.dll', "/r:$sma",
        "/resource:$src\GameBoost.ps1,GameBoost.ps1", "/resource:$third\PresentMon-x64.exe,PresentMon-x64.exe",
        "/resource:$third\PresentMon-x86.exe,PresentMon-x86.exe", "/resource:$third\LICENSE.txt,PresentMon-LICENCE.txt") + $extra + @("$L\Launcher.cs"))
}
function Build-Setup([string]$out, [string]$app, [string]$manifest, [string[]]$extra) {
    Invoke-Csc (@('/nologo', '/nowarn:162,429', '/target:winexe', '/optimize+', "/out:$out", "/win32manifest:$manifest", "/win32icon:$L\GameBoost.ico",
        '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:Microsoft.CSharp.dll',
        "/resource:$app,GameBoost.exe", "/resource:$L\logo.png,logo.png",
        "/resource:$src\..\LISEZ-MOI.txt,LISEZ-MOI.txt", "/resource:$src\..\LICENSE,LICENCE.txt") + $extra + @("$I\Setup.cs"))
}

$app = Join-Path $OutDir 'GameBoost.exe'; $setup = Join-Path $OutDir 'GameBoost-Setup.exe'
Build-App $app @()
Build-Setup $setup $app "$I\setup.manifest" @()

# Verification : le script integre dans l'exe est bien celui du dossier
$asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($app))
$st = $asm.GetManifestResourceStream('GameBoost.ps1'); $ms = New-Object IO.MemoryStream; $st.CopyTo($ms)
$same = [Convert]::ToBase64String($ms.ToArray()) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $src 'GameBoost.ps1')))
if (-not $same) { throw "Le script integre dans GameBoost.exe ne correspond pas a GameBoost.ps1." }

if ($Test) {
    $t = Join-Path $OutDir 'test'; New-Item -ItemType Directory -Force $t | Out-Null
    Build-App (Join-Path $t 'GameBoostTest.exe') @('/define:TEST')
    Build-Setup (Join-Path $t 'SetupTest.exe') $app "$L\app.manifest" @('/define:TEST')
}
Get-ChildItem $OutDir -Filter *.exe | ForEach-Object { '{0,-22} {1,9:N0} octets  v{2}' -f $_.Name, $_.Length, $_.VersionInfo.FileVersion }


