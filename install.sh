#!/bin/bash
# Proteus - instala (ou atualiza) no Linux
# Copia o script sob e sobrescreve a versão anterior.
# Offline: não conecta na internet.

set -uo pipefail

INSTALL_DIR="/usr/local/bin"
TARGET="$INSTALL_DIR/proteus"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SRC_DIR/proteus"

# confere que o arquivo fonte tá aqui
if [[ ! -f "$SRC" ]]; then
    echo "[proteus-installer] Erro: 'proteus' nao encontrado em $SRC_DIR" >&2
    exit 1
fi

# root obrigatório
if [[ $EUID -ne 0 ]]; then
    echo "[proteus-installer] Requer root. Rode: sudo $0" >&2
    exit 1
fi

# cria o dir se não existir
if [[ ! -d "$INSTALL_DIR" ]]; then
    mkdir -p "$INSTALL_DIR"
fi

# se já tem versão instalada, sobrescreve
if [[ -f "$TARGET" ]]; then
    OLD_VER=$(grep -m1 '^# Proteus v' "$TARGET" 2>/dev/null | sed 's/.*v//')
    echo "[proteus-installer] Versao antiga encontrada${OLD_VER:+ (v$OLD_VER)}. Sobrescrevendo..."
else
    echo "[proteus-installer] Nenhuma versao anterior encontrada. Instalando..."
fi

# copia e acerta a permissão
cp -f "$SRC" "$TARGET"
chmod 755 "$TARGET"

echo "[proteus-installer] Instalado em: $TARGET"
echo "[proteus-installer] Verifique com: proteus --help"
exit 0
