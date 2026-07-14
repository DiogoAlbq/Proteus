<#
.SYNOPSIS
Proteus Windows port for setting processor affinity by physical core groups.

.DESCRIPTION
This script attempts to allocate full physical cores to a launched process by
selecting logical processor groups based on CPU core counts and SMT ratio.
#>

$DEFAULT_PERCENT = 75

function Show-Usage {
    Write-Output @"
Proteus Windows port

Uso: .\proteus.ps1 [--cores N | --percent N] -- <comando> [args...]

Opções:
  --cores N       Dedica N núcleos físicos completos ao processo
  --percent N     Dedica N% dos núcleos físicos totais (padrão: $DEFAULT_PERCENT%)
  -h, --help      Mostra esta ajuda
"@
    exit 0
}

function Get-ProcessorInfo {
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        return Get-CimInstance -ClassName Win32_Processor
    }
    if (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
        return Get-WmiObject -Class Win32_Processor
    }

    Write-Error "[proteus] Erro: nenhum provedor WMI disponível para obter informações de CPU"
    exit 1
}

$coresArg = $null
$percentArg = $null
$positionals = @()

while ($args.Count -gt 0) {
    switch ($args[0]) {
        '--cores' {
            if ($args.Count -lt 2 -or $args[1].StartsWith('--')) {
                Write-Error "[proteus] Erro: --cores requer um valor"
                exit 1
            }
            $coresArg = $args[1]
            $args = $args[2..($args.Count - 1)]
            continue
        }
        '--percent' {
            if ($args.Count -lt 2 -or $args[1].StartsWith('--')) {
                Write-Error "[proteus] Erro: --percent requer um valor"
                exit 1
            }
            $percentArg = $args[1]
            $args = $args[2..($args.Count - 1)]
            continue
        }
        '-h' | '--help' {
            Show-Usage
        }
        '--' {
            $args = $args[1..($args.Count - 1)]
            break
        }
        default {
            break
        }
    }
}

if ($args.Count -eq 0) {
    Show-Usage
}

$command = $args[0]
$commandArgs = @()
if ($args.Count -gt 1) {
    $commandArgs = $args[1..($args.Count - 1)]
}

$processors = Get-ProcessorInfo
$physicalCores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
$logicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

if ($physicalCores -le 0) {
    Write-Error "[proteus] Erro: não foi possível detectar núcleos físicos"
    exit 1
}

if ($logicalProcessors -lt $physicalCores) {
    $logicalProcessors = $physicalCores
}

if ($coresArg) {
    if ($coresArg -notmatch '^[0-9]+$' -or [int]$coresArg -lt 1) {
        Write-Error "[proteus] --cores deve ser inteiro positivo"
        exit 1
    }
    $targetCores = [int]$coresArg
} elseif ($percentArg) {
    if ($percentArg -notmatch '^[0-9]+$') {
        Write-Error "[proteus] --percent deve ser inteiro 1-100"
        exit 1
    }
    $percent = [int]$percentArg
    if ($percent -lt 1 -or $percent -gt 100) {
        Write-Error "[proteus] --percent deve ser 1-100"
        exit 1
    }
    $targetCores = [math]::Ceiling($physicalCores * $percent / 100.0)
} else {
    $targetCores = [math]::Ceiling($physicalCores * $DEFAULT_PERCENT / 100.0)
}

if ($targetCores -lt 1) { $targetCores = 1 }
if ($targetCores -gt $physicalCores) { $targetCores = $physicalCores }

$threadsPerCore = 1
if ($logicalProcessors % $physicalCores -eq 0) {
    $threadsPerCore = [int]($logicalProcessors / $physicalCores)
} else {
    Write-Host "[proteus] aviso: topologia SMT irregular detectada, usando 1 thread por core" -ForegroundColor Yellow
}

$selectedThreads = @()
for ($coreIndex = 0; $coreIndex -lt $targetCores; $coreIndex++) {
    for ($threadIndex = 0; $threadIndex -lt $threadsPerCore; $threadIndex++) {
        $selectedThreads += ($coreIndex * $threadsPerCore + $threadIndex)
    }
}

$maxThread = ($selectedThreads | Measure-Object -Maximum).Maximum
if ($maxThread -ge 64) {
    Write-Error "[proteus] Erro: mais de 64 threads lógicas não são suportadas pelo affinity mask atual"
    exit 1
}

$affinityMask = [uint64]0
foreach ($thread in $selectedThreads) {
    $affinityMask = $affinityMask -bor ([uint64]1 -shl $thread)
}

Write-Host "[proteus] físico: ${physicalCores}C/${threadsPerCore}T | alocado: ${targetCores} cores (${selectedThreads.Count} threads: $($selectedThreads -join ', ')) | affinity: 0x$([Convert]::ToString($affinityMask,16))" -ForegroundColor Yellow

try {
    $process = Start-Process -FilePath $command -ArgumentList $commandArgs -PassThru
    $process.ProcessorAffinity = [intptr]$affinityMask
    $process.WaitForExit()
    exit $process.ExitCode
} catch {
    Write-Error "[proteus] Erro ao iniciar o comando: $_"
    exit 1
}
