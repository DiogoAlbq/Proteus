# Proteus - instalador Windows
# Copia proteus.ps1 sobrescrevendo a versão anterior.
# Offline: não conecta na internet.

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$InstallDir = "$env:USERPROFILE"
$Target = Join-Path $InstallDir "proteus.ps1"

# resolve a pasta do script (fallback se $PSScriptRoot for $null)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$Src = Join-Path $scriptDir "proteus.ps1"

# confere que o arquivo fonte tá na pasta
if (-not (Test-Path $Src)) {
    Write-Error "[proteus-installer] Erro: 'proteus.ps1' nao encontrado em $scriptDir"
    exit 1
}

# já tem versão antiga? sobrescrevemos
if (Test-Path $Target) {
    $old = Select-String -Path $Target -Pattern "^# Proteus v" -ErrorAction SilentlyContinue
    $oldVer = if ($old) { $old.Matches.Value -replace "^# Proteus v", "" } else { "" }
    Write-Host "[proteus-installer] Versao antiga encontrada$(if ($oldVer) { " (v$oldVer)" }). Sobrescrevendo..."
} else {
    Write-Host "[proteus-installer] Nenhuma versao anterior encontrada. Instalando..."
}

# garante destino
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# copia na marra (Force sobrescreve)
Copy-Item -Path $Src -Destination $Target -Force

# confirma se copiou
if (Test-Path $Target) {
    Write-Host "[proteus-installer] Instalado em: $Target"
    Write-Host "[proteus-installer] Verifique com: powershell -File $Target --help"
} else {
    Write-Error "[proteus-installer] Falha: arquivo nao foi copiado"
    exit 1
}
exit 0
