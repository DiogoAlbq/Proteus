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

MIT

## Autor

Orion
