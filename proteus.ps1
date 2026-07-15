# Proteus - wrapper pra alocar núcleos físicos de CPU a um processo (porte Windows).
# Feito pra quem joga no Windows e quer Affinidade + limite de RAM/cota de CPU sem complicação.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$VERSION = "1.1.0"
$DEFAULT_PERCENT = 75

function Show-Usage {
    Write-Output @"
Proteus v$VERSION - CPU physical core allocation wrapper (Windows)

Uso: proteus.ps1 [OPCOES] <comando> [args...]

Opcoes de CPU:
  --cores N       Dedica N nucleos fisicos completos ao processo
  --percent N     Dedica N% dos nucleos fisicos totais (padrao: $DEFAULT_PERCENT%)
  --cpu N         Limita o uso de CPU do processo a N% (1-100, cota de CPU)

Opcoes de memoria:
  --mem N         Limita o processo a N MB de RAM (ex: --mem 4096 = 4 GB)
  --ram N         Limita o processo a N% da RAM total (ex: --ram 50 = metade)

Opcoes de GPU (informacao/deteccao):
  --vram N        Define um target de N MB de VRAM e mostra info da GPU detectada
  --gpuram N      Define um target de N% da VRAM total (ex: --gpuram 50 = metade)

  -h, --help      Mostra esta ajuda
  -v, --version   Mostra a versao

Exemplos (Ryzen 7 5700X = 8 cores fisicos / 16 threads):
  .\proteus.ps1 .\jogo.exe                  # 75% = 6 cores (0-5 + SMT)
  .\proteus.ps1 --percent 100 .\jogo.exe    # 100% = 8 cores (todos)
  .\proteus.ps1 --percent 50 .\jogo.exe     # 50%  = 4 cores (0-3 + SMT)
  .\proteus.ps1 --cores 4 .\jogo.exe        # Exatos 4 cores (0-3 + SMT)
  .\proteus.ps1 --mem 4096 .\jogo.exe       # 4 GB de RAM max
  .\proteus.ps1 --ram 50 .\jogo.exe          # 50% da RAM total
  .\proteus.ps1 --cpu 50 .\jogo.exe          # Limita processo a 50% de CPU
  .\proteus.ps1 --vram 2048 .\jogo.exe       # Target 2 GB VRAM + info GPU
  .\proteus.ps1 --gpuram 50 .\jogo.exe       # Target 50% VRAM + info GPU
  .\proteus.ps1 --cores 4 --mem 6144 .\jogo.exe  # 4 cores, 6 GB RAM
  .\proteus.ps1 --cores 4 --cpu 80 --ram 50 .\jogo.exe  # 4 cores, 80% CPU, 50% RAM

Integracao:
  Steam:        powershell -File proteus.ps1 %command%
  Heroic:       powershell -File proteus.ps1 (Wrapper Command)
  Bottles:      powershell -File proteus.ps1 %command%
"@
    exit 0
}

# lê os argumentos
$CoresArg   = $null
$PercentArg = $null
$MemArg     = $null
$RamArg     = $null
$CpuArg     = $null
$VramArg    = $null
$GpuramArg  = $null
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
        "--mem" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --mem requer um valor (MB)" -ErrorAction Stop
            }
            $MemArg = $args[$i + 1]; $i++
        }
        "--ram" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --ram requer um valor (1-100)" -ErrorAction Stop
            }
            $RamArg = $args[$i + 1]; $i++
        }
        "--cpu" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --cpu requer um valor (1-100)" -ErrorAction Stop
            }
            $CpuArg = $args[$i + 1]; $i++
        }
        "--vram" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --vram requer um valor (MB)" -ErrorAction Stop
            }
            $VramArg = $args[$i + 1]; $i++
        }
        "--gpuram" {
            if (($i + 1) -ge $args.Length -or $args[$i + 1] -match "^-{1,2}") {
                Write-Error "[proteus] Erro: --gpuram requer um valor (1-100)" -ErrorAction Stop
            }
            $GpuramArg = $args[$i + 1]; $i++
        }
        "-h" { Show-Usage }
        "--help" { Show-Usage }
        "-v" { Write-Output "proteus $VERSION"; exit 0 }
        "--version" { Write-Output "proteus $VERSION"; exit 0 }
        "--" { $Parsing = $false }
        default { $Parsing = $false; $Command += $args[$i] }
    }
}

if ($Command.Count -eq 0) { Show-Usage }

# detecta CPU via WMI - tenta CIM primeiro, fallback pra WMI
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

# soma cores físicos e threads lógicas
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

# threads por core (SMT)
$threadsPerCore = 1
$smtWarn = $false
if (($logicalThreads % $physicalCores) -eq 0) {
    $threadsPerCore = [int]($logicalThreads / $physicalCores)
} else {
    $threadsPerCore = 1
    $smtWarn = $true
}

# quantos cores físicos vamos usar
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

# não deixa passar do total
if ($targetCores -lt 1) { $targetCores = 1 }
if ($targetCores -gt $physicalCores) { $targetCores = $physicalCores }

# monta lista de threads lógicas (primeiros N cores * threads por core)
$selectedThreads = [System.Collections.ArrayList]::new()
for ($core = 0; $core -lt $targetCores; $core++) {
    for ($t = 0; $t -lt $threadsPerCore; $t++) {
        $logical = ($core * $threadsPerCore) + $t
        if ($logical -lt $logicalThreads) {
            [void]$selectedThreads.Add($logical)
        }
    }
}

# limite de RAM (--mem MB ou --ram %)
$memLimitBytes = [uint64]0
$memInfo = ""

if ($MemArg -and $RamArg) {
    Write-Error "[proteus] Erro: use --mem OU --ram, nao ambos" -ErrorAction Stop
}

if ($MemArg) {
    if ($MemArg -notmatch "^\d+$" -or [uint64]$MemArg -lt 1) {
        Write-Error "[proteus] --mem deve ser inteiro positivo (MB)" -ErrorAction Stop
    }
    $memLimitBytes = ([uint64]$MemArg) * 1024 * 1024
    $memInfo = "${MemArg}MB"
} elseif ($RamArg) {
    if ($RamArg -notmatch "^\d+$" -or [int]$RamArg -lt 1 -or [int]$RamArg -gt 100) {
        Write-Error "[proteus] --ram deve ser inteiro 1-100" -ErrorAction Stop
    }
    # RAM total via Win32_OperatingSystem (em KB)
    $totalRamKB = 0
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalRamKB = [uint64]$os.TotalVisibleMemorySize
    } catch {
        try {
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $totalRamKB = [uint64]$os.TotalVisibleMemorySize
        } catch {
            Write-Warning "[proteus] Nao foi possivel ler RAM total; limite de RAM nao aplicado"
        }
    }
    if ($totalRamKB -gt 0) {
        $totalRamBytes = $totalRamKB * 1024
        $memLimitBytes = [uint64]([math]::Floor($totalRamBytes * ([int]$RamArg) / 100.0))
        $memInfo = "${RamArg}% RAM"
    }
}

# P/Invoke pra kernel32 - Job Objects e controle de CPU rate
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class JobObject {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll")]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll")]
    public static extern bool SetInformationJobObject(IntPtr hJob, int infoType, IntPtr lpJobInfo, uint cbJobInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    // structs do Job Object pra limite de RAM
    // JOBOBJECT_BASIC_LIMIT_INFORMATION
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public long Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    // bitfield flags
    public const int JobObjectExtendedLimitInformation = 9;
    public const int JobObjectCpuRateControlInformation = 15;
    public const uint JOB_OBJECT_LIMIT_PROCESS_MEMORY = 0x100;
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    public const uint JOB_OBJECT_CPU_RATE_CONTROL_ENABLE = 0x1;
    public const uint JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP = 0x4;

    // JOBOBJECT_CPU_RATE_CONTROL_INFORMATION
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_CPU_RATE_CONTROL_INFORMATION {
        public uint ControlFlags;
        public uint CpuRate;
    }
}
"@

$jobHandle = [IntPtr]::Zero

# cota de CPU (--cpu N%)
$cpuQuotaRate = 0
$cpuQuotaInfo = ""

if ($CpuArg) {
    if ($CpuArg -notmatch "^\d+$" -or [int]$CpuArg -lt 1 -or [int]$CpuArg -gt 100) {
        Write-Error "[proteus] --cpu deve ser inteiro 1-100" -ErrorAction Stop
    }
    # CpuRate = percent * 100 (50% vira 5000)
    $cpuQuotaRate = ([int]$CpuArg) * 100
    $cpuQuotaInfo = "${CpuArg}% CPU"
}

function Set-ProcessLimits([IntPtr]$processHandle, [uint64]$memBytes, [int]$cpuRate) {
    $jobHandle = [JobObject]::CreateJobObject([IntPtr]::Zero, $null)
    if ($jobHandle -eq [IntPtr]::Zero) {
        Write-Warning "[proteus] Falha ao criar Job Object"
        return [IntPtr]::Zero
    }

    # Limites estendidos = RAM
    if ($memBytes -gt 0) {
        $extended = New-Object JobObject+JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        $extended.BasicLimitInformation.LimitFlags = [JobObject]::JOB_OBJECT_LIMIT_PROCESS_MEMORY -bor [JobObject]::JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        $extended.ProcessMemoryLimit = [UIntPtr]$memBytes

        $size = [System.Runtime.InteropServices.Marshal]::SizeOf($extended)
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($size)
        try {
            [System.Runtime.InteropServices.Marshal]::StructureToPtr($extended, $ptr, $false)
            $ok = [JobObject]::SetInformationJobObject($jobHandle, [JobObject]::JobObjectExtendedLimitInformation, $ptr, $size)
            if (-not $ok) {
                Write-Warning "[proteus] Falha ao definir limite de memoria no Job Object"
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
        }
    }

    # Cota de CPU via rate control
    if ($cpuRate -gt 0) {
        $cpu = New-Object JobObject+JOBOBJECT_CPU_RATE_CONTROL_INFORMATION
        $cpu.ControlFlags = [JobObject]::JOB_OBJECT_CPU_RATE_CONTROL_ENABLE -bor [JobObject]::JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP
        $cpu.CpuRate = [uint32]$cpuRate

        $size = [System.Runtime.InteropServices.Marshal]::SizeOf($cpu)
        $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($size)
        try {
            [System.Runtime.InteropServices.Marshal]::StructureToPtr($cpu, $ptr, $false)
            $ok = [JobObject]::SetInformationJobObject($jobHandle, [JobObject]::JobObjectCpuRateControlInformation, $ptr, $size)
            if (-not $ok) {
                Write-Warning "[proteus] Falha ao definir cota de CPU no Job Object"
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
        }
    }

    $assigned = [JobObject]::AssignProcessToJobObject($jobHandle, $processHandle)
    if (-not $assigned) {
        Write-Warning "[proteus] Falha ao assignar processo ao Job Object"
        [JobObject]::CloseHandle($jobHandle) | Out-Null
        return [IntPtr]::Zero
    }

    return $jobHandle
}

# mascara de afinidade (uint64) — cabe até 64 threads
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
$cpuInfo = "fisico: ${physicalCores}C/$tpc | alocado: $targetCores cores ($($selectedThreads.Count) threads: $threadList)"
$ramInfo = if ($memLimitBytes -gt 0) { " | RAM limit: $memInfo" } else { "" }
$cpuLog = if ($cpuQuotaInfo) { " | CPU quota: $cpuQuotaInfo" } else { "" }

# info da GPU (--vram MB ou --gpuram %) - informativo, não limita de verdade
$gpuLog = ""

if ($VramArg -and $GpuramArg) {
    Write-Error "[proteus] Erro: use --vram OU --gpuram, nao ambos" -ErrorAction Stop
}

if ($VramArg) {
    if ($VramArg -notmatch "^\d+$" -or [int]$VramArg -lt 1) {
        Write-Error "[proteus] --vram deve ser inteiro positivo (MB)" -ErrorAction Stop
    }
}

if ($GpuramArg) {
    if ($GpuramArg -notmatch "^\d+$" -or [int]$GpuramArg -lt 1 -or [int]$GpuramArg -gt 100) {
        Write-Error "[proteus] --gpuram deve ser inteiro 1-100" -ErrorAction Stop
    }
}

if ($VramArg -or $GpuramArg) {
    $gpuName = ""
    $gpuVramTotalMB = 0

    # NVIDIA via nvidia-smi
    try {
        $smiPath = "nvidia-smi"
        $gpuName = (& $smiPath --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1)
        $gpuVramTotalMB = [int](& $smiPath --query-gpu=memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
    } catch {
        $gpuName = ""
    }

    if ($gpuName -and $gpuVramTotalMB -gt 0) {
        if ($VramArg) {
            $gpuLog = " | GPU: $gpuName ($gpuVramTotalMB MB total) | VRAM target: $VramArg MB"
        } else {
            $targetVram = [int]([math]::Floor($gpuVramTotalMB * ([int]$GpuramArg) / 100.0))
            $gpuLog = " | GPU: $gpuName ($gpuVramTotalMB MB total) | VRAM target: $targetVram MB ($GpuramArg%)"
        }
    } elseif ($gpuName) {
        $gpuLog = " | GPU: $gpuName (sem info de VRAM)"
    } else {
        if ($VramArg) {
            $gpuLog = " | GPU: nao detectada | VRAM target: $VramArg MB (nao aplicavel)"
        } else {
            $gpuLog = " | GPU: nao detectada | VRAM target: $GpuramArg% (nao aplicavel)"
        }
    }
}

Write-Host "[proteus] $cpuInfo$ramInfo$cpuLog$gpuLog" -ForegroundColor Cyan

# executa o processo, aplica afinidade e limites (RAM + CPU)
try {
    $p = Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Length - 1)]) -PassThru -NoNewWindow
    try {
        $p.ProcessorAffinity = [IntPtr]$affinityMask
    } catch {
        Write-Warning "[proteus] Falha ao aplicar ProcessorAffinity: $($_.Exception.Message)"
    }

    $jobHandle = [IntPtr]::Zero
    if (($memLimitBytes -gt 0) -or ($cpuQuotaRate -gt 0)) {
        try {
            $hProcess = $p.Handle
            $jobHandle = Set-ProcessLimits $hProcess $memLimitBytes $cpuQuotaRate
            if ($jobHandle -ne [IntPtr]::Zero) {
                # segura o handle pra não morrer antes do processo
                $script:ActiveJobHandle = $jobHandle
            }
        } catch {
            Write-Warning "[proteus] Falha ao aplicar limites: $($_.Exception.Message)"
        }
    }

    $p.WaitForExit()
    $exitCode = $p.ExitCode

    if ($jobHandle -ne [IntPtr]::Zero) {
        [JobObject]::CloseHandle($jobHandle) | Out-Null
    }

    exit $exitCode
} catch {
    Write-Error "[proteus] Erro ao iniciar processo: $($_.Exception.Message)"
    exit 1
}
