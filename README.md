# Proteus

Lightweight CLI wrapper that dedicates **physical CPU cores** (with all SMT threads) to a single process. Built for latency-sensitive games and apps on Linux and Windows.

## Features

- **CPU affinity** — pin a process to N physical cores (or a % of total)
- **CPU quota** — throttle the process to N% of total CPU time (`--cpu`)
- **RAM limit** — cap memory to N MB or N% of total (`--mem` / `--ram`)
- **GPU detection** — detect GPU and show VRAM info (`--vram` / `--gpuram`)
- Linux via `taskset` + `systemd-run` cgroups; Windows via PowerShell Job Objects

## Requirements

| Platform | Requirements |
|---|---|
| **Linux** | `taskset`, `lscpu`. Optional: `gamemoderun`, `systemd-run` (for `--mem`/`--ram`/`--cpu`) |
| **Windows** | Windows 10+, PowerShell 5.1+, WMI access |

## Install

### Linux

```bash
git clone https://github.com/DiogoAlbq/Proteus.git
cd Proteus
sudo bash install.sh
```

> Re-run `sudo bash install.sh` any time to update — it overwrites the old version. No internet needed.

### Windows

```powershell
git clone https://github.com/DiogoAlbq/Proteus.git
cd Proteus
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

> Re-run `install.ps1` any time to update. Installs to `%USERPROFILE%\proteus.ps1`.

## Usage

```
proteus [OPTIONS] <command> [args...]
```

### Options

| Option | Description |
|---|---|
| `--cores N` | Allocate exactly N physical cores |
| `--percent N` | Allocate N% of physical cores (default: 75) |
| `--cpu N` | Limit process to N% of total CPU time (1-100) |
| `--mem N` | Limit process to N MB of RAM |
| `--ram N` | Limit process to N% of total RAM |
| `--vram N` | Set VRAM target (N MB) and show GPU info |
| `--gpuram N` | Set VRAM target (N% of total) and show GPU info |
| `-h`, `--help` | Show help |
| `-v`, `--version` | Show version |
| `--` | Separate options from command |

### Examples

```bash
# Linux
proteus ./game
proteus --cores 4 ./game
proteus --percent 50 ./game
proteus --cpu 50 ./game
proteus --mem 4096 ./game
proteus --ram 50 ./game
proteus --cores 4 --cpu 80 --ram 50 ./game
```

```powershell
# Windows
.\proteus.ps1 .\game.exe
.\proteus.ps1 --cores 4 .\game.exe --fullscreen
.\proteus.ps1 --mem 4096 .\game.exe
```

## Launcher Integration

| Launcher | Linux | Windows |
|---|---|---|
| Steam | `proteus %command%` | `powershell -File proteus.ps1 %command%` |
| Lutris | Command Prefix: `proteus` | `powershell -File proteus.ps1` |
| Heroic | Wrapper: `proteus` | Wrapper: `powershell -File proteus.ps1` |
| Bottles | `proteus %command%` | `powershell -File proteus.ps1 %command%` |

> Bottles Flatpak: `flatpak override --user --filesystem=/usr/local/bin:ro com.usebottles.bottles`

## 8C/16T Example

| Command | Cores | Threads | RAM | CPU |
|---|---|---|---|---|
| `proteus ./game` | 6 | 12 | — | — |
| `proteus --percent 100 ./game` | 8 | 16 | — | — |
| `proteus --cores 4 ./game` | 4 | 8 | — | — |
| `proteus --mem 4096 ./game` | 6 | 12 | 4 GB | — |
| `proteus --cores 4 --cpu 80 --ram 50 ./game` | 4 | 8 | 50% | 80% |

## Behavior

- `--cores` or `--percent` above the total → clamps to max
- `--mem` + `--ram` together → error
- `--vram` + `--gpuram` together → error
- No `taskset` → runs without affinity
- No `systemd-run` → warns and skips RAM/CPU limits (affinity still applies)
- No `--mem`/`--ram`/`--cpu` → no resource limits applied

## GPU Limits

`--vram` and `--gpuram` **detect** the GPU (NVIDIA via `nvidia-smi`, AMD via `rocm-smi`) and show VRAM info in the log. The target value is **informational**.

## How It Works

### Linux

1. Reads CPU topology via `lscpu -p=CPU,CORE,SOCKET`
2. Groups logical threads by physical core
3. Selects the first N physical cores and all their SMT threads
4. Builds a CPU list for `taskset -c`
5. If `--mem`/`--ram`: reads `/proc/meminfo`, applies `MemoryMax` via `systemd-run --scope --user`
6. If `--cpu`: applies `CPUQuota` via `systemd-run`
7. Runs the command with `taskset` + `gamemoderun` (if available)

### Windows

1. Detects CPU via `Get-CimInstance Win32_Processor` (fallback: `Get-WmiObject`)
2. Sums `NumberOfCores` and `NumberOfLogicalProcessors` across sockets
3. Builds a `uint64` affinity mask (limit: 64 threads)
4. If `--mem`/`--ram`: reads RAM via `Win32_OperatingSystem`, creates a Job Object with `JOB_OBJECT_LIMIT_PROCESS_MEMORY`
5. If `--cpu`: sets `JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP` on the Job Object
6. Starts the process with `Start-Process`, applies `ProcessorAffinity` and assigns to the Job Object

## License

MIT — see [LICENSE](LICENSE).
