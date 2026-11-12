param([string]$Src, [string]$Out)
# Test reel (droits administrateur) du bouton GPU de GameBoost sur la vraie carte NVIDIA, puis remise d'origine
$log = New-Object System.Collections.ArrayList
function W($m) { [void]$log.Add([string]$m) }
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    W ("Droits administrateur : " + $isAdmin)
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Src, [ref]$tokens, [ref]$errs)
    $want = 'Get-GBGpuCtlInfo','Get-GBGpuReco','Get-GBGpuWant','Set-GBGpuCap','Update-GBGpuCap','ConvertTo-GBNum','Find-GBNvidiaSmi','Invoke-GBSmi'
    foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { if ($want -contains $f.Name) { . ([scriptblock]::Create($f.Extent.Text)) } }
    function Log($m) { W ("  journal GameBoost : " + $m) }
    function Save-Config {}
    $vc = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    $Script:MainGpu = @{ Name = $vc.Name; KindLabel = 'carte graphique dediee'; VramGo = 8; DriverVersion = $vc.DriverVersion }
    $Script:Config = [ordered]@{ GpuEco = $false; GpuOnMhz = 0; GpuEcoMhz = 0; GpuPowerMax = $false; GpuLocked = $false; GpuPlSet = $false; GpuPlDefault = 0; GpuNoLock = '' }
    $Script:RealConfig = $null; $Script:Boosted = $false
    $smi = Find-GBNvidiaSmi
    function Q { $r = & $smi --query-gpu=clocks.gr,clocks.max.gr,power.draw,temperature.gpu --format=csv,noheader 2>&1; return ($r -join ' ') }
    function Reasons { return ((& $smi -q -d PERFORMANCE 2>&1) | Select-String 'Applications Clocks Setting|SW Power Cap|Idle' | ForEach-Object { $_.Line.Trim() }) -join ' | ' }
    $i = Get-GBGpuCtlInfo
    W ("Carte : " + $i.Name + " | max " + $i.MaxMhz + " MHz | verrouillage possible : " + $i.CanLock + " | puissance reglable : " + $i.CanPower)
    W ("Avant : " + (Q))

    W "== 1. Commande officielle nvidia-smi directe : verrou a 1400 MHz"
    $o = & $smi -lgc 0,1400 2>&1; W ("  code " + $LASTEXITCODE + " : " + ($o -join ' '))
    W ("  pendant : " + (Q) + " | " + (Reasons))
    $o = & $smi -rgc 2>&1; W ("  remise -rgc : code " + $LASTEXITCODE + " : " + ($o -join ' '))

    W "== 2. GameBoost : bouton GPU : ECO (valeur conseillee)"
    $Script:Config.GpuEco = $true; Update-GBGpuCap
    W ("  verrou applique par GameBoost : " + $Script:Config.GpuLocked + " | " + (Q))
    W "== 3. GameBoost : boost en cours (limite levee)"
    $Script:Boosted = $true; $Script:Config.GpuPowerMax = $true; Update-GBGpuCap
    W ("  verrou : " + $Script:Config.GpuLocked + " | puissance changee : " + $Script:Config.GpuPlSet + " | " + (Q))
    W "== 4. GameBoost : fin du boost (ECO remis)"
    $Script:Boosted = $false; Update-GBGpuCap
    W ("  verrou : " + $Script:Config.GpuLocked)
    W "== 5. GameBoost : GPU ON limite a 2,6 GHz"
    $Script:Config.GpuEco = $false; $Script:Config.GpuOnMhz = 2600; Update-GBGpuCap
    W ("  verrou : " + $Script:Config.GpuLocked)
    W "== 6. Puissance (OC) sur ce portable"
    $o = & $smi -pl 115 2>&1; W ("  -pl 115 : code " + $LASTEXITCODE + " : " + ($o -join ' '))
    W "== 7. Fermeture de GameBoost : tout remis"
    Set-GBGpuCap $false
    W ("  verrou : " + $Script:Config.GpuLocked + " | puissance changee : " + $Script:Config.GpuPlSet)
} catch { W ("ERREUR : " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) }
finally {
    # Securite : frequence d'origine quoi qu'il arrive
    try { $o = & (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe') -rgc 2>&1; W ("Remise finale (-rgc) : " + ($o -join ' ')) } catch {}
    try { W ("Apres : " + ((& (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe') --query-gpu=clocks.gr,clocks.max.gr,power.limit,enforced.power.limit --format=csv,noheader 2>&1) -join ' ')) } catch {}
    [IO.File]::WriteAllLines($Out, [string[]]$log.ToArray())
}
