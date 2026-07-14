# Proteus

Proteus é um wrapper de linha de comando minimalista para alocar **núcleos físicos de CPU** a um processo por execução.
Ele usa `lscpu` para montar uma máscara de CPU que inclui **todas as threads SMT** dos cores físicos selecionados e aplica essa máscara com `taskset`.

## Visão geral

Proteus foi criado para melhorar o comportamento de jogos e aplicativos sensíveis a latência no Linux.
Ele reduz a contenção SMT ao garantir que o processo execute em núcleos físicos completos, não apenas em threads lógicas isoladas.

## Requisitos

- Linux
- `taskset` (coreutils)
- `lscpu` (util-linux)
- `gamemoderun` (opcional)
- `systemd-run` (opcional, necessário para `--mem`/`--ram`)

---

# Porta Windows (`proteus.ps1`)

O arquivo `proteus.ps1` é uma porta para Windows em PowerShell que define afinidade de processador usando a propriedade `ProcessorAffinity` do processo. Ele suporta `--cores`, `--percent`, `--mem` e `--ram` de forma equivalente ao script Linux, usando `Win32_Processor` (WMI/CIM) para detectar a topologia de CPU e `Win32_OperatingSystem` para a RAM total. O limite de memória é aplicado via **Job Objects** (`JOBOBJECT_EXTENDED_LIMIT_INFORMATION`).

## Requisitos (Windows)

- Windows 10 / 11 ou Windows Server 2016+
- PowerShell 5.1 ou superior
- Acesso a WMI/CIM para as classes `Win32_Processor` e `Win32_OperatingSystem`
- Permissão para alterar afinidade do processo e criar Job Objects (conta padrão do usuário normalmente basta)

## Uso (Windows)

```powershell
.\proteus.ps1 [OPÇÕES] <comando> [args...]
```

Opções:

- `--cores N` — aloca exatamente `N` núcleos físicos completos
- `--percent N` — aloca `N%` dos núcleos físicos totais (padrão: 75%)
- `--mem N` — limita o processo a `N` MB de RAM (ex: `--mem 4096` = 4 GB)
- `--ram N` — limita o processo a `N%` da RAM total (ex: `--ram 50` = metade)
- `-h`, `--help` — exibe a ajuda
- `--` — separa opções do comando (útil para comandos que começam com `-`)

### Exemplos (Windows)

```powershell
.\proteus.ps1 .\jogo.exe
.\proteus.ps1 --percent 100 .\jogo.exe
.\proteus.ps1 --percent 50 .\jogo.exe
.\proteus.ps1 --cores 4 .\jogo.exe --fullscreen
.\proteus.ps1 --mem 4096 .\jogo.exe
.\proteus.ps1 --ram 50 .\jogo.exe
.\proteus.ps1 --cores 4 --mem 6144 .\jogo.exe
```

## Instalação (Windows)

### Opção 1 — Via git clone + instalador (recomendado)

```powershell
git clone https://github.com/DiogoAlbq/Proteus.git
cd Proteus
.\install.ps1
```

### Opção 2 — Baixar ZIP e rodar o instalador

Baixe o ZIP do repositório, extraia em qualquer pasta e execute:

```powershell
.\install.ps1
```

> O instalador copia `proteus.ps1` para `%USERPROFILE%\proteus.ps1` **sobrescrevendo** qualquer versão anterior, sem conectarse à internet.

### Verificação (Windows)

```powershell
.\proteus.ps1 --help
```

## Como funciona (Windows)

1. Detecta a topologia de CPU via `Get-CimInstance Win32_Processor` (fallback para `Get-WmiObject`)
2. Soma `NumberOfCores` (físicos) e `NumberOfLogicalProcessors` (lógicos) entre todos os sockets
3. Calcula threads por core (SMT); se lógico não é múltiplo de físico, usa fallback de 1T/core com aviso
4. Calcula quantos cores físicos alocar (`--cores`, `--percent`, ou padrão 75%)
5. Seleciona os primeiros `N` cores físicos e todas as suas threads SMT
6. Constrói uma máscara de afinidade `uint64` com bits correspondentes às threads selecionadas (limite: 64 threads)
7. Se `--mem`/`--ram` foi passado, lê a RAM total via `Win32_OperatingSystem` e calcula o limite em bytes
8. Inicia o comando com `Start-Process -PassThru`, aplica `$process.ProcessorAffinity`, cria um **Job Object** com `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` + `JOB_OBJECT_LIMIT_PROCESS_MEMORY` e assigna o processo ao Job
9. Espera o término e retorna o código de saída

## Integração com launchers (Windows)

| Launcher | Configuração |
|---|---|
| Steam | `powershell -File proteus.ps1 %command%` |
| Heroic | Wrapper Command: `powershell -File proteus.ps1` |
| Bottles | `powershell -File proteus.ps1 %command%` |
| Lutris (Windows) | Command Prefix: `powershell -File proteus.ps1` |

## Limitações da porta Windows

- A máscara de afinidade é `uint64`, limitando o suporte a **64 threads lógicas**
- O Windows não expõe a topologia de forma tão granular quanto `lscpu` no Linux; a assumição linear (core `i` → threads `i*threadsPerCore` a `(i+1)*threadsPerCore - 1`) pode não refletir a ordem real do kernel em sistemas NUMA complexos
- Se `NumberOfLogicalProcessors` não for múltiplo de `NumberOfCores`, o script assume 1 thread/core e exibe um aviso
- Sem equivalente ao `gamemoderun` no Windows; a afinidade é aplicada via `ProcessorAffinity`
- O limite de RAM via Job Object usa `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`: se o PowerShell for fechado, o processo limitado também é terminado
- Processos já associados a outro Job Object podem falhar ao ser assignados (raro em Windows 10+ com JobObjects aninhados habilitados)

## Uso

```bash
proteus [OPÇÕES] <comando> [args...]
```

Opções de CPU:

- `--cores N` — aloca exatamente `N` núcleos físicos completos
- `--percent N` — aloca `N%` dos núcleos físicos totais (padrão: 75%)

Opções de memória:

- `--mem N` — limita o processo a `N` MB de RAM (ex: `--mem 4096` = 4 GB)
- `--ram N` — limita o processo a `N%` da RAM total (ex: `--ram 50` = metade)

Outras:

- `-h`, `--help` — exibe a ajuda
- `--` — separa opções do comando

## Exemplos

```bash
proteus ./jogo
proteus --percent 100 ./jogo
proteus --percent 50 ./jogo
proteus --cores 4 ./jogo
proteus --mem 4096 ./jogo
proteus --ram 50 ./jogo
proteus --cores 4 --mem 6144 ./jogo
```

## Instalação

### Opção 1 — Via git clone + instalador (recomendado)

```bash
git clone https://github.com/DiogoAlbq/Proteus.git
cd Proteus
sudo ./install.sh
```

### Opção 2 — Baixar ZIP/tar e rodar o instalador

Baixe o repositório como ZIP, extraia em qualquer pasta e execute:

```bash
sudo ./install.sh
```

> O instalador copia `proteus` para `/usr/local/bin/proteus` **sobrescrevendo** qualquer versão anterior, sem se conectar à internet.

### Verificação

Após a instalação, verifique se o comando está disponível:

```bash
proteus --help
```

## Atualização

### Linux

A atualização é igual à instalação: rode `sudo ./install.sh` novamente e ele sobrescreve a versão antiga:

```bash
# Se usou git clone:
cd Proteus
git pull
sudo ./install.sh

# Se baixou ZIP novo:
# Extraia e rode: sudo ./install.sh
```

### Windows

A atualização é igual à instalação: rode `.\install.ps1` novamente e ele sobrescreve a versão antiga:

```powershell
# Se usou git clone:
cd Proteus
git pull
.\install.ps1

# Se baixou ZIP novo:
# Extraia e rode: .\install.ps1
```

## Como funciona

1. Lê a topologia real de CPU com `lscpu -p=CPU,CORE,SOCKET`
2. Agrupa threads lógicas por core físico
3. Calcula quantos cores físicos alocar
4. Seleciona os primeiros `N` cores físicos na ordem do kernel
5. Monta a lista de threads SMT para `taskset -c`
6. Se `--mem`/`--ram` foi passado, lê a RAM total em `/proc/meminfo` e calcula o limite em bytes
7. Executa o comando com `taskset` + `gamemoderun` (se disponível); se limite de RAM ativo, envolve tudo com `systemd-run --scope --user -p MemoryMax=...`

## Integração com launchers

| Launcher | Configuração |
|---|---|
| Steam | `proteus %command%` |
| Lutris | Command Prefix: `proteus` |
| Heroic | Wrapper Command: `proteus` |
| Bottles | Launch Options: `proteus %command%` |

> Para Bottles Flatpak:
> `flatpak override --user --filesystem=/usr/local/bin:ro com.usebottles.bottles`

## Comportamento esperado

- `--cores > total` → clampa para o total de cores físicos
- `--percent > 100` → clampa para 100%
- `--percent < 1` → usa mínimo de 1 core
- `--mem` e `--ram` juntos → erro e sai
- Sem `gamemoderun` → roda apenas com `taskset`
- Sem `taskset` → executa o comando diretamente
- Sem `systemd-run` → avisa e roda sem limite de RAM (apenas CPU)
- Sem `--mem`/`--ram` → nenhum limite de memória aplicado

## Exemplo prático

Para um sistema 8C/16T:

- `proteus ./jogo` — 75% = 6 cores físicos (12 threads)
- `proteus --percent 100 ./jogo` — 8 cores físicos (16 threads)
- `proteus --percent 50 ./jogo` — 4 cores físicos (8 threads)
- `proteus --cores 4 ./jogo` — 4 cores físicos exatos
- `proteus --mem 4096 ./jogo` — 6 cores + limite de 4 GB RAM
- `proteus --ram 50 ./jogo` — 6 cores + 50% da RAM total
- `proteus --cores 4 --mem 6144 ./jogo` — 4 cores + 6 GB RAM

## Por que núcleos físicos?

Núcleos físicos completos evitam que a thread principal do jogo seja colocada em um par SMT instável com outra carga intensa.
Isso melhora previsibilidade, IPC e latência em workloads single-thread sensíveis.

## Licença

Este projeto está licenciado sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para detalhes.

---
