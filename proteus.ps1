# Proteus — CPU physical core allocation wrapper (Windows PowerShell port)
# Dedica ncleos fisicos completos (ambas threads SMT) a um processo no Windows.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$DEFAULT_PERCENT = 75

function Show-Usage {
    Write-Output @"
Proteus - CPU physical core allocation wrapper (Windows)

Uso: proteus.ps1 [OPCOES] <comando> [args...]

Opcoes de CPU:
  --cores N       Dedica N nucleos fisicos completos ao processo
  --percent N     Dedica N% dos nucleos fisicos totais (padrao: $DEFAULT_PERCENT%)

Opcoes de memoria:
  --mem N         Limita o processo a N MB de RAM (ex: --mem 4096 = 4 GB)
  --ram N         Limita o processo a N% da RAM total (ex: --ram 50 = metade)

  -h, --help      Mostra esta ajuda

Exemplos (Ryzen 7 5700X = 8 cores fisicos / 16 threads):
  .\proteus.ps1 .\jogo.exe                  # 75% = 6 cores (0-5 + SMT)
  .\proteus.ps1 --percent 100 .\jogo.exe    # 100% = 8 cores (todos)
  .\proteus.ps1 --percent 50 .\jogo.exe     # 50%  = 4 cores (0-3 + SMT)
  .\proteus.ps1 --cores 4 .\jogo.exe        # Exatos 4 cores (0-3 + SMT)
  .\proteus.ps1 --mem 4096 .\jogo.exe       # 4 GB de RAM max
  .\proteus.ps1 --ram 50 .\jogo.exe          # 50% da RAM total
  .\proteus.ps1 --cores 4 --mem 6144 .\jogo.exe  # 4 cores, 6 GB RAM

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
$MemArg     = $null
$RamArg     = $null
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
# ---------------------------------------------------------------------------
# 6b. Calcular limite de memoria (--mem MB ou --ram %)
# ---------------------------------------------------------------------------
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
    # RAM total via Win32_OperatingSystem (TotalVisibleMemorySize em KB)
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

# ---------------------------------------------------------------------------
# 6c. Helpers P/Invoke para Job Objects (limite de memoria no Windows)
# ---------------------------------------------------------------------------
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

    public const int JobObjectExtendedLimitInformation = 9;
    public const uint JOB_OBJECT_LIMIT_PROCESS_MEMORY = 0x100;
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
}
"@

$jobHandle = [IntPtr]::Zero

function Set-ProcessMemoryLimit([IntPtr]$processHandle, [uint64]$memBytes) {
    $jobHandle = [JobObject]::CreateJobObject([IntPtr]::Zero, $null)
    if ($jobHandle -eq [IntPtr]::Zero) {
        Write-Warning "[proteus] Falha ao criar Job Object"
        return [IntPtr]::Zero
    }

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
            [JobObject]::CloseHandle($jobHandle) | Out-Null
            return [IntPtr]::Zero
        }
    } finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }

    $assigned = [JobObject]::AssignProcessToJobObject($jobHandle, $processHandle)
    if (-not $assigned) {
        Write-Warning "[proteus] Falha ao assignar processo ao Job Object"
        [JobObject]::CloseHandle($jobHandle) | Out-Null
        return [IntPtr]::Zero
    }

    return $jobHandle
}

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
Write-Host "[proteus] $cpuInfo$ramInfo" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 7. Executar o comando com afinidade e/ou limite de memoria aplicados
# ---------------------------------------------------------------------------
try {
    $p = Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Length - 1)]) -PassThru -NoNewWindow
    try {
        $p.ProcessorAffinity = [IntPtr]$affinityMask
    } catch {
        Write-Warning "[proteus] Falha ao aplicar ProcessorAffinity: $($_.Exception.Message)"
    }

    $jobHandle = [IntPtr]::Zero
    if ($memLimitBytes -gt 0) {
        try {
            $hProcess = $p.Handle
            $jobHandle = Set-ProcessMemoryLimit $hProcess $memLimitBytes
            if ($jobHandle -ne [IntPtr]::Zero) {
                # mantem handle vivo para o Job nao ser destruido antes do processo
                $script:ActiveJobHandle = $jobHandle
            }
        } catch {
            Write-Warning "[proteus] Falha ao aplicar limite de RAM: $($_.Exception.Message)"
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
