# Proteus — CPU physical core allocation wrapper (Windows PowerShell port)
# Dedica ncleos fisicos completos (ambas threads SMT) a um processo no Windows.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$DEFAULT_PERCENT = 75

function Show-Usage {
    Write-Output @"
Proteus - CPU physical core allocation wrapper (Windows)

Uso: proteus.ps1 [OPCOES] <comando> [args...]

Opcoes:
  --cores N       Dedica N nucleos fisicos completos ao processo
  --percent N     Dedica N% dos nucleos fisicos totais (padrao: $DEFAULT_PERCENT%)
  -h, --help      Mostra esta ajuda

Exemplos (Ryzen 7 5700X = 8 cores fisicos / 16 threads):
  .\proteus.ps1 .\jogo.exe                  # 75% = 6 cores (0-5 + SMT)
  .\proteus.ps1 --percent 100 .\jogo.exe    # 100% = 8 cores (todos)
  .\proteus.ps1 --percent 50 .\jogo.exe     # 50%  = 4 cores (0-3 + SMT)
  .\proteus.ps1 --cores 4 .\jogo.exe        # Exatos 4 cores (0-3 + SMT)

Integracao:
  Steam:        powershell -File proteus.ps1 %command%
  Heroic:       powershell -File proteus.ps1 (Wrapper Command)
  Bottles:      powershell -File proteus.ps1 %command%
"@
    exit 0
}

# ---------------------------------------------------------------------------
# Parser de argumentos
# ---------------------------------------------------------------------------
$CoresArg   = $null
$PercentArg = $null
$Command    = @()
$Parsing    = $true
$SkipNext   = $false

for ($i = 0; $i -lt $args.Length; $i++) {
    if (-not $Parsing) { $Command += $args[$i]; continue }

    switch ($args[$i]) {
        "--cores" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --cores requer um valor" -ErrorAction Stop
            }
            $CoresArg = $args[$i + 1]; $i++
        }
        "--percent" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --percent requer um valor" -ErrorAction Stop
            }
            $PercentArg = $args[$i + 1]; $i++
        }
        "-h" { Show-Usage }
        "--help" { Show-Usage }
        "--" { $Parsing = $false }
        default { $Parsing = $false; $Command += $args[$i] }
    }
}

if ($Command.Count -eq 0) { Show-Usage }

# ---------------------------------------------------------------------------
# 2. Deteccao de CPU via WMI/CIM
# ---------------------------------------------------------------------------
$processors = $null
try {
    $processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
} catch {
    try {
        $processors = Get-WmiObject -Class Win32_Processor -ErrorAction Stop
    } catch {
        Write-Warning "[proteus] Nao foi possivel ler a topologia de CPU via WMI/CIM"
    }
}

if (-not $processors) {
    Write-Output "[proteus] Executando sem afinidade (CPU nao detectada)"
    $p = Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Length - 1)]) -PassThru -NoNewWindow
    $p.WaitForExit()
    exit $p.ExitCode
}

# ---------------------------------------------------------------------------
# 3. Calculo da topologia
# ---------------------------------------------------------------------------
$physicalCores = 0
$logicalThreads = 0
foreach ($cpu in $processors) {
    $physicalCores += [int]$cpu.NumberOfCores
    $logicalThreads += [int]$cpu.NumberOfLogicalProcessors
}

if ($logicalThreads -le 0 -or $physicalCores -le 0) {
    Write-Warning "[proteus] Topologia invalida; executando sem afinidade"
    $p = Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Length - 1)]) -PassThru -NoNewWindow
    $p.WaitForExit()
    exit $p.ExitCode
}

# Threads por core (SMT)
$threadsPerCore = 1
$smtWarn = $false
if (($logicalThreads % $physicalCores) -eq 0) {
    $threadsPerCore = [int]($logicalThreads / $physicalCores)
} else {
    $threadsPerCore = 1
    $smtWarn = $true
}

# ---------------------------------------------------------------------------
# 4. Determinar numero de cores a alocar
# ---------------------------------------------------------------------------
$targetCores = 0
if ($CoresArg) {
    if ($CoresArg -notmatch "^\d+$" -or [int]$CoresArg -lt 1) {
        Write-Error "[proteus] --cores deve ser inteiro positivo" -ErrorAction Stop
    }
    $targetCores = [int]$CoresArg
} elseif ($PercentArg) {
    if ($PercentArg -notmatch "^\d+$" -or [int]$PercentArg -lt 1 -or [int]$PercentArg -gt 100) {
        Write-Error "[proteus] --percent deve ser inteiro 1-100" -ErrorAction Stop
    }
    $targetCores = [math]::Ceiling(($physicalCores * [int]$PercentArg) / 100.0)
} else {
    $targetCores = [math]::Ceiling(($physicalCores * $DEFAULT_PERCENT) / 100.0)
}

# Clamp
if ($targetCores -lt 1) { $targetCores = 1 }
if ($targetCores -gt $physicalCores) { $targetCores = $physicalCores }

# ---------------------------------------------------------------------------
# 5. Montar lista de threads logicas selecionadas (primeiros N cores fisicos)
# ---------------------------------------------------------------------------
$selectedThreads = [System.Collections.ArrayList]::new()
for ($core = 0; $core -lt $targetCores; $core++) {
    for ($t = 0; $t -lt $threadsPerCore; $t++) {
        $logical = ($core * $threadsPerCore) + $t
        if ($logical -lt $logicalThreads) {
            [void]$selectedThreads.Add($logical)
        }
    }
}

# ---------------------------------------------------------------------------
# 6. Gerar mascara de afinidade (ProcessorAffinity)
# Limite: 64 threads logicas (uint64)
# ---------------------------------------------------------------------------
if ($selectedThreads.Count -gt 64) {
    Write-Warning "[proteus] Mais de 64 threads detectadas; limitando a 64"
    $selectedThreads = $selectedThreads[0..63]
}

$affinityMask = [uint64]0
foreach ($t in $selectedThreads) {
    $affinityMask = $affinityMask -bor ([uint64]1 -shl $t)
}

if ($smtWarn) {
    Write-Warning "[proteus] Threads logicas nao sao multiplo dos fisicos; assumindo 1 thread/core"
}

$threadList = ($selectedThreads -join ",")
$tpc = if ($smtWarn) { "1T (fallback)" } else { "${threadsPerCore}T" }
Write-Host "[proteus] fisico: ${physicalCores}C/$tpc | alocado: $targetCores cores ($($selectedThreads.Count) threads: $threadList)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 7. Executar o comando com afinidade aplicada
# ---------------------------------------------------------------------------
try {
    $p = Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Length - 1)]) -PassThru -NoNewWindow
    try {
        $p.ProcessorAffinity = [IntPtr]$affinityMask
    } catch {
        Write-Warning "[proteus] Falha ao aplicar ProcessorAffinity: $($_.Exception.Message)"
    }
    $p.WaitForExit()
    exit $p.ExitCode
} catch {
    Write-Error "[proteus] Erro ao iniciar processo: $($_.Exception.Message)"
    exit 1
}
