#!/bin/bash
# Proteus — Instalador Linux
# Copia o script para o PATH sobrescrevendo qualquer versao anterior.
# Nao conecta à internet; apenas sobrescreve localmente.

set -uo pipefail

INSTALL_DIR="/usr/local/bin"
TARGET="$INSTALL_DIR/proteus"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SRC_DIR/proteus"

# Verifica que o script-fonte existe
if [[ ! -f "$SRC" ]]; then
    echo "[proteus-installer] Erro: 'proteus' nao encontrado em $SRC_DIR" >&2
    exit 1
fi

# Verifica perms de root
if [[ $EUID -ne 0 ]]; then
    echo "[proteus-installer] Requer root. Rode: sudo $0" >&2
    exit 1
fi

# Garante que o dir de destino exista
if [[ ! -d "$INSTALL_DIR" ]]; then
    mkdir -p "$INSTALL_DIR"
fi

# Detecta versao antiga
if [[ -f "$TARGET" ]]; then
    OLD_VER=$(grep -m1 '^# Proteus v' "$TARGET" 2>/dev/null | sed 's/.*v//')
    echo "[proteus-installer] Versao antiga encontrada${OLD_VER:+ (v$OLD_VER)}. Sobrescrevendo..."
else
    echo "[proteus-installer] Nenhuma versao anterior encontrada. Instalando..."
fi

# Copia sobrescrevendo, ajusta perms
cp -f "$SRC" "$TARGET"
chmod 755 "$TARGET"

echo "[proteus-installer] Instalado em: $TARGET"
echo "[proteus-installer] Verifique com: proteus --help"
exit 0
