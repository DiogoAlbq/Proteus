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

---

# Porta Windows (`proteus.ps1`)

O arquivo `proteus.ps1` é uma porta para Windows em PowerShell que define afinidade de processador usando a propriedade `ProcessorAffinity` do processo. Ele suporta `--cores` e `--percent` de forma equivalente ao script Linux, usando `Win32_Processor` (WMI/CIM) para detectar a topologia de CPU.

## Requisitos (Windows)

- Windows 10 / 11 ou Windows Server 2016+
- PowerShell 5.1 ou superior
- Acesso a WMI/CIM para a classe `Win32_Processor`
- Permissão para alterar afinidade do processo (conta padrão do usuário normalmente basta)

## Uso (Windows)

```powershell
.\proteus.ps1 [OPÇÕES] <comando> [args...]
```

Opções:

- `--cores N` — aloca exatamente `N` núcleos físicos completos
- `--percent N` — aloca `N%` dos núcleos físicos totais (padrão: 75%)
- `-h`, `--help` — exibe a ajuda
- `--` — separa opções do comando (útil para comandos que começam com `-`)

### Exemplos (Windows)

```powershell
.\proteus.ps1 .\jogo.exe
.\proteus.ps1 --percent 100 .\jogo.exe
.\proteus.ps1 --percent 50 .\jogo.exe
.\proteus.ps1 --cores 4 .\jogo.exe --fullscreen
```

## Instalação (Windows)

### Opção 1 — Via git clone

```powershell
git clone https://github.com/DiogoAlbq/Proteus.git
cd Proteus
# Opcional: copiar para uma pasta no PATH
Copy-Item proteus.ps1 "$env:USERPROFILE\proteus.ps1"
```

### Opção 2 — Download manual

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DiogoAlbq/Proteus/main/proteus.ps1" -OutFile "proteus.ps1"
```

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
7. Inicia o comando com `Start-Process -PassThru`, aplica `$process.ProcessorAffinity`, espera o término e retorna o código de saída

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

## Uso

```bash
proteus [--cores N | --percent N] <comando> [args...]
```

Opções:

- `--cores N` — aloca exatamente `N` núcleos físicos completos
- `--percent N` — aloca `N%` dos núcleos físicos totais
- `-h`, `--help` — exibe a ajuda

## Exemplos

```bash
proteus ./jogo
proteus --percent 100 ./jogo
proteus --percent 50 ./jogo
proteus --cores 4 ./jogo
```

## Instalação

### Opção 1 — Via git clone (recomendado)

Clone o repositório e instale o script no `PATH`:

```bash
git clone https://github.com/DiogoAlbq/Proteus.git
cd Proteus
sudo cp proteus /usr/local/bin/proteus
sudo chmod 755 /usr/local/bin/proteus
```

Para atualizar no futuro, basta rodar `git pull` dentro da pasta clonada e repetir o `cp`.

### Opção 2 — Instalação manual (sem git)

Baixe o arquivo `proteus` diretamente do GitHub e instale:

```bash
curl -fsSL https://raw.githubusercontent.com/DiogoAlbq/Proteus/main/proteus -o /tmp/proteus
sudo cp /tmp/proteus /usr/local/bin/proteus
sudo chmod 755 /usr/local/bin/proteus
```

Ou, sem `curl`, usando `wget`:

```bash
wget -qO /tmp/proteus https://raw.githubusercontent.com/DiogoAlbq/Proteus/main/proteus
sudo cp /tmp/proteus /usr/local/bin/proteus
sudo chmod 755 /usr/local/bin/proteus
```

### Verificação

Após a instalação, verifique se o comando está disponível:

```bash
proteus --help
```

## Como funciona

1. Lê a topologia real de CPU com `lscpu -p=CPU,CORE,SOCKET`
2. Agrupa threads lógicas por core físico
3. Calcula quantos cores físicos alocar
4. Seleciona os primeiros `N` cores físicos na ordem do kernel
5. Monta a lista de threads SMT para `taskset -c`
6. Executa o comando com `taskset` e `gamemoderun` (se disponível)

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
- Sem `gamemoderun` → roda apenas com `taskset`
- Sem `taskset` → executa o comando diretamente

## Exemplo prático

Para um sistema 8C/16T:

- `proteus ./jogo` — 75% = 6 cores físicos (12 threads)
- `proteus --percent 100 ./jogo` — 8 cores físicos (16 threads)
- `proteus --percent 50 ./jogo` — 4 cores físicos (8 threads)
- `proteus --cores 4 ./jogo` — 4 cores físicos exatos

## Por que núcleos físicos?

Núcleos físicos completos evitam que a thread principal do jogo seja colocada em um par SMT instável com outra carga intensa.
Isso melhora previsibilidade, IPC e latência em workloads single-thread sensíveis.

## Licença

Este projeto está licenciado sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para detalhes.

---
