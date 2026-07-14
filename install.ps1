# Proteus — Instalador Windows (PowerShell)
# Copia proteus.ps1 sobrescrevendo qualquer versao anterior.
# Nao conecta à internet; apenas sobrescreve localmente.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$InstallDir = "$env:USERPROFILE"
$Target = Join-Path $InstallDir "proteus.ps1"
$Src = Join-Path $PSScriptRoot "proteus.ps1"

# Verifica que o script-fonte existe
if (-not (Test-Path $Src)) {
    Write-Error "[proteus-installer] Erro: 'proteus.ps1' nao encontrado em $PSScriptRoot"
    exit 1
}

# Detecta versao antiga
if (Test-Path $Target) {
    $old = Select-String -Path $Target -Pattern "^# Proteus v" -ErrorAction SilentlyContinue
    $oldVer = if ($old) { $old.Matches.Value -replace "^# Proteus v", "" } else { "" }
    Write-Host "[proteus-installer] Versao antiga encontrada$(if ($oldVer) { " (v$oldVer)" }). Sobrescrevendo..."
} else {
    Write-Host "[proteus-installer] Nenhuma versao anterior encontrada. Instalando..."
}

# Garante que o dir de destino exista
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Copia sobrescrevendo (Force)
Copy-Item -Path $Src -Destination $Target -Force

# Verificacao
if (Test-Path $Target) {
    Write-Host "[proteus-installer] Instalado em: $Target"
    Write-Host "[proteus-installer] Verifique com: powershell -File $Target --help"
} else {
    Write-Error "[proteus-installer] Falha: arquivo nao foi copiado"
    exit 1
}
exit 0
