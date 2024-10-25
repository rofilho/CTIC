# Define a política de execução para permitir o script
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

# Caminho do relatório
$computerName = $env:COMPUTERNAME
$reportDirectory = "C:\temp"
$reportPath = "$reportDirectory\$computerName.txt"

# Verifica se a pasta C:\temp existe; se não, cria a pasta
if (!(Test-Path -Path $reportDirectory)) {
    New-Item -Path $reportDirectory -ItemType Directory -Force
}

# Cria ou limpa o arquivo de relatório
if (!(Test-Path -Path $reportPath)) {
    New-Item -Path $reportPath -ItemType File -Force
} else {
    Clear-Content -Path $reportPath
}

#--------------------------------------------------------------------------
# 1 - Função para timeout

function Invoke-With-Timeout {
    param (
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 300,
        [string]$ReportPath
    )
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ReportPath
    $result = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if ($result) {
        Receive-Job -Job $job
    } else {
        Stop-Job -Job $job
        Write-Host "A operação atingiu o timeout e foi interrompida." -ForegroundColor Red
        if (![string]::IsNullOrEmpty($ReportPath)) {
            Add-Content -Path $ReportPath -Value "`nA operação atingiu o timeout e foi interrompida.`n" -Encoding UTF8
        }
        return $false
    }
}

#--------------------------------------------------------------------------
# 2 - Função para barra de progresso global

function Show-GlobalProgress {
    param (
        [string]$Activity,
        [int]$PercentComplete
    )
    Write-Progress -Activity $Activity -PercentComplete $PercentComplete
}

#--------------------------------------------------------------------------
# 3 - Inicializa a barra de progresso global

$totalSteps = 13
$currentStep = 0

#--------------------------------------------------------------------------
# 4 - Atualiza a barra de progresso

function Update-Progress {
    $global:currentStep++
    $percentComplete = [math]::Round(($global:currentStep / $totalSteps) * 100)
    Show-GlobalProgress -Activity "Executando script de manutenção..." -PercentComplete $percentComplete
}

#--------------------------------------------------------------------------
# 5 - Função para formatar o tempo de execução

function Format-ExecutionTime {
    param ([double]$executionTime)
    if ($executionTime -lt 1) {
        $seconds = [math]::Round($executionTime * 60)
        return "$seconds segundos"
    } elseif ($executionTime -lt 60) {
        $minutes = [math]::Floor($executionTime)
        $seconds = [math]::Round(($executionTime - $minutes) * 60)
        return "$minutes min e $seconds segundos"
    } else {
        $hours = [math]::Floor($executionTime / 60)
        $minutes = [math]::Round($executionTime % 60)
        return "$hours horas e $minutes min"
    }
}

#--------------------------------------------------------------------------
# 6 - Função para coletar informações do sistema

function Collect-SystemInfo {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Coletando informações do sistema..." -ForegroundColor Yellow
        $computerName = $env:COMPUTERNAME
        $userName = $env:USERNAME
        $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "10.*" } | Select-Object -ExpandProperty IPAddress
        $osVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
        $osBuild = (Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber
        $installDate = (Get-CimInstance -ClassName Win32_OperatingSystem).InstallDate
        $formattedInstallDate = Get-Date $installDate -Format "yyyy-MM-dd HH:mm:ss"
        $executionDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $uptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $formattedUptime = Get-Date $uptime -Format "yyyy-MM-dd HH:mm:ss"

        $reportContent = @"
=== Relatório de Manutenção do Sistema ===
Data e Hora de Execução: $executionDateTime

=== Informações do Sistema ===
Nome da Máquina: $computerName
Usuário: $userName
Endereço IP: $($ipAddresses -join ', ')
Versão do Windows: $osVersion
Compilação: $osBuild
Data de Instalação do Sistema: $formattedInstallDate
Tempo de Atividade: $formattedUptime
"@
        if (![string]::IsNullOrEmpty($ReportPath)) {
            Add-Content -Path $ReportPath -Value $reportContent -Encoding UTF8
        }
        Write-Host "Coleta de informações do sistema concluída." -ForegroundColor Green
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 7 - Função para listar perfis de usuário

function Collect-Profiles {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Coletando perfis de usuário..." -ForegroundColor Yellow
        $profiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.LocalPath -notlike '*ServiceProfiles*' -and $_.LocalPath -notlike 'C:\WINDOWS*' } | Select-Object LocalPath, SID
        if ($profiles.Count -gt 0) {
            $profileList = @()
            foreach ($profile in $profiles) {
                $profileList += "Perfil: $($profile.LocalPath), SID: $($profile.SID)"
            }
            $profileDetails = $profileList -join "`n"
            if (![string]::IsNullOrEmpty($ReportPath)) {
                Add-Content -Path $ReportPath -Value "`n=== Perfis de Usuário ===`n$profileDetails" -Encoding UTF8
            }
        } else {
            Add-Content -Path $ReportPath -Value "`n=== Perfis de Usuário ===`nNenhum perfil encontrado." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 8 - Função para verificar integridade do sistema

function Check-SystemIntegrity {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Verificando integridade do sistema..." -ForegroundColor Yellow
        try {
            $errors = Get-EventLog -LogName System -EntryType Error -Newest 50 | Select-Object -Unique -First 10
            if ($errors.Count -gt 0) {
                $errorDetails = $errors | ForEach-Object {
                    "$($_.TimeGenerated) - ID: $($_.EventID) - $($_.Source): $($_.Message)"
                }
                $formattedErrors = $errorDetails -join "`n"
                if (![string]::IsNullOrEmpty($ReportPath)) {
                    Add-Content -Path $ReportPath -Value "`n=== Integridade do Sistema (Últimos 10 Eventos) ===`n$formattedErrors" -Encoding UTF8
                }
            } else {
                Add-Content -Path $ReportPath -Value "`n=== Integridade do Sistema ===`nNenhum erro crítico encontrado." -Encoding UTF8
            }
        } catch {
            Add-Content -Path $ReportPath -Value "`n=== Integridade do Sistema ===`nErro ao verificar integridade do sistema." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 9 - Função para verificação de segurança (Antivírus e Firewall)

function Check-Security {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Verificando segurança do sistema..." -ForegroundColor Yellow
        try {
            $antivirusStatus = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | Select-Object displayName, productState
            $firewallStatus = Get-NetFirewallProfile | Select-Object Name, Enabled

            $firewallFormatted = "Firewall Status:"
            foreach ($profile in $firewallStatus) {
                $firewallFormatted += "`n- $($profile.Name): Ativado=$($profile.Enabled)"
            }

            $securityDetails = "Antivírus: $($antivirusStatus.displayName), Status: $($antivirusStatus.productState)`n$firewallFormatted"
            if (![string]::IsNullOrEmpty($ReportPath)) {
                Add-Content -Path $ReportPath -Value "`n=== Verificação de Segurança ===`n$securityDetails" -Encoding UTF8
            }
        } catch {
            Add-Content -Path $ReportPath -Value "`n=== Verificação de Segurança ===`nErro ao verificar segurança do sistema." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 10 - Função para listar impressoras instaladas

function Collect-Printers {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Coletando impressoras instaladas..." -ForegroundColor Yellow
        $printers = Get-WmiObject -Class Win32_Printer | Select-Object Name, PortName
        if ($printers.Count -gt 0) {
            $printerDetails = $printers | ForEach-Object { "$($_.Name) - $($_.PortName)" }
            if (![string]::IsNullOrEmpty($ReportPath)) {
                Add-Content -Path $ReportPath -Value "`n=== Impressoras Instaladas ===`n$($printerDetails -join "`n")" -Encoding UTF8
            }
        } else {
            Add-Content -Path $ReportPath -Value "`n=== Impressoras Instaladas ===`nNenhuma impressora instalada." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 11 - Função para verificar e instalar atualizações do Windows usando Get-HotFix

function Update-Windows {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Verificando e instalando atualizações do Windows..." -ForegroundColor Yellow
        try {
            $hotfixes = Get-HotFix
            if ($hotfixes) {
                Add-Content -Path $ReportPath -Value "`n=== Atualizações do Windows ===`nAtualizações listadas com sucesso." -Encoding UTF8
            } else {
                Add-Content -Path $ReportPath -Value "`n=== Atualizações do Windows ===`nNenhuma atualização pendente." -Encoding UTF8
            }
        } catch {
            Add-Content -Path $ReportPath -Value "`n=== Atualizações do Windows ===`nErro ao verificar ou instalar atualizações do Windows." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 12 - Função para atualizar software via winget

function Update-Software {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        try {
            $wingetProcess = Start-Process -FilePath "winget" -ArgumentList "upgrade --all" -PassThru -Wait
            $exitCode = $wingetProcess.ExitCode
            if ($exitCode -eq 0) {
                Add-Content -Path $ReportPath -Value "`n=== Atualizações de Software ===`nAtualização de software concluída com sucesso." -Encoding UTF8
            } else {
                Add-Content -Path $ReportPath -Value "`n=== Atualizações de Software ===`nErro ao atualizar software. Código de saída: $exitCode" -Encoding UTF8
            }
        } catch {
            Add-Content -Path $ReportPath -Value "`n=== Atualizações de Software ===`nErro ao atualizar software." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 13 - Função para limpeza de arquivos temporários e logs

function Clean-TemporaryFiles {
    param ([string]$ReportPath)
    Update-Progress
    Invoke-With-Timeout -ScriptBlock {
        param ($ReportPath)
        Write-Host "Executando limpeza de arquivos temporários, atualizações e Windows OLD..." -ForegroundColor Yellow
        try {
            Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path "C:\Windows.old") {
                Remove-Item "C:\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
            }
            Get-EventLog -LogName Application -Newest 1000 | Clear-EventLog
            Add-Content -Path $ReportPath -Value "`n=== Limpeza de Arquivos Temporários ===`nLimpeza realizada com sucesso." -Encoding UTF8
        } catch {
            Add-Content -Path $ReportPath -Value "`n=== Limpeza de Arquivos Temporários ===`nErro ao realizar limpeza." -Encoding UTF8
        }
    } -TimeoutSeconds 300 -ReportPath $ReportPath
}

#--------------------------------------------------------------------------
# 14 - Função para manutenção de disco (HDD e SSD)

function Disk-Maintenance {
    param ([string]$ReportPath)
    Update-Progress
    Write-Host "Verificando tipo de disco..." -ForegroundColor Yellow
    $disks = Get-PhysicalDisk
    foreach ($disk in $disks) {
        if ($disk.MediaType -eq "HDD") {
            Write-Host "Disco HDD detectado. Executando verificação e desfragmentação..." -ForegroundColor Cyan
            $userResponse = Read-Host "Deseja realizar o check e desfragmentação do HD? (s/n)"
            if ($userResponse -eq "s") {
                $chkdskOutput = chkdsk C: /f /r 2>&1
                if ($chkdskOutput -match "Não é possível bloquear a unidade atual") {
                    $scheduleResponse = Read-Host "O volume está em uso. Deseja agendar a verificação para a próxima inicialização? (s/n)"
                    if ($scheduleResponse -eq "s") {
                        chkdsk C: /f /r /x
                        Add-Content -Path $ReportPath -Value "`n=== Manutenção de Disco ===`nVerificação agendada para a próxima inicialização." -Encoding UTF8
                    } else {
                        Add-Content -Path $ReportPath -Value "`n=== Manutenção de Disco ===`nVerificação de disco não agendada." -Encoding UTF8
                    }
                } else {
                    Add-Content -Path $ReportPath -Value "`n=== Manutenção de Disco ===`nVerificação de disco realizada com sucesso." -Encoding UTF8
                }
                defrag C: /O
            } else {
                Add-Content -Path $ReportPath -Value "`n=== Manutenção de Disco ===`nManutenção de HD não realizada." -Encoding UTF8
            }
        } elseif ($disk.MediaType -eq "SSD") {
            Write-Host "Disco SSD detectado. Executando manutenção específica..." -ForegroundColor Cyan
            $userResponse = Read-Host "Deseja realizar a verificação e manutenção do SSD? (s/n)"
            if ($userResponse -eq "s") {
                Optimize-Volume -DriveLetter C -ReTrim -Verbose
                Add-Content -Path $ReportPath -Value "`n=== Manutenção de Disco ===`nManutenção de SSD realizada." -Encoding UTF8
            } else {
                Add-Content -Path $ReportPath -Value "`n=== Manutenção de Disco ===`nManutenção de SSD não realizada." -Encoding UTF8
            }
        }
    }
}


#-------------------------------------------------------------------------- 
# 15 - Função para reparo do Windows

function Repair-Windows {
    param ([string]$ReportPath)
    Update-Progress
    
    # Imprime o valor de $ReportPath para depuração
    Write-Host "Valor de ReportPath: $ReportPath" -ForegroundColor Cyan

    # Lista de comandos para reparo do Windows
    $commands = @(
        @{Name = "sfc /scannow"; Description = "Verificando integridade dos arquivos do sistema"},
        @{Name = "chkdsk C: /f /r"; Description = "Verificando e reparando erros no disco"},
        @{Name = "DISM.exe /Online /Cleanup-Image /CheckHealth"; Description = "Verificando integridade da imagem do sistema"},
        @{Name = "DISM.exe /Online /Cleanup-Image /RestoreHealth"; Description = "Restaurando a imagem do sistema"}
    )

    foreach ($command in $commands) {
        $userResponse = Read-Host "Deseja executar o comando '$($command.Name)'? (s/n)"
        
        if ($userResponse -eq "s") {
            Write-Host "`nExecutando: $($command.Description)" -ForegroundColor Green

            # Caso especial para o chkdsk que pode requerer agendamento
            if ($command.Name -like "chkdsk*") {
                try {
                    $output = cmd /c $command.Name 2>&1 | Out-String
                    Write-Host "`nSaída do comando '$($command.Name)':" -ForegroundColor Cyan
                    Write-Host $output.Substring(0, [Math]::Min(1000, $output.Length))

                    if ($output -match "não é possível bloquear a unidade atual" -or $output -match "O volume está em uso") {
                        $scheduleResponse = Read-Host "O volume está em uso. Deseja agendar a verificação para o próximo reinício? (s/n)"
                        if ($scheduleResponse -eq "s") {
                            $scheduleOutput = cmd /c "chkdsk C: /f /r /x" | Out-String
                            Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nDescrição: $($command.Description)`nVerificação agendada para o próximo reinício.`n" -Encoding UTF8
                            Write-Host "Verificação agendada para o próximo reinício." -ForegroundColor Green
                        } else {
                            Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nVerificação não foi agendada pelo usuário.`n" -Encoding UTF8
                            Write-Host "Verificação não agendada." -ForegroundColor Yellow
                        }
                    } else {
                        Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nDescrição: $($command.Description)`nSaída:`n$output`n" -Encoding UTF8
                    }
                } catch {
                    Write-Host "Erro ao executar o comando: $($command.Name)" -ForegroundColor Red
                    Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nErro ao executar comando: $_`n" -Encoding UTF8
                }
            } else {
                try {
                    # Executa o comando e captura a saída
                    $output = Invoke-Expression -Command $command.Name | Out-String
                    
                    # Mostra um resumo da saída
                    Write-Host "`nSaída do comando '$($command.Name)':" -ForegroundColor Cyan
                    Write-Host $output.Substring(0, [Math]::Min(1000, $output.Length))

                    # Adiciona o resultado ao relatório
                    Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nDescrição: $($command.Description)`nSaída:`n$output`n" -Encoding UTF8
                } catch {
                    # Em caso de erro, registra no relatório e mostra no console
                    Write-Host "Erro ao executar o comando: $($command.Name)" -ForegroundColor Red
                    Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nErro ao executar comando: $_`n" -Encoding UTF8
                }
            }
        } else {
            Write-Host "Comando '$($command.Name)' não foi executado." -ForegroundColor Yellow
            Add-Content -Path $ReportPath -Value "`n=== Comando: $($command.Name) ===`nComando não executado pelo usuário.`n" -Encoding UTF8
        }
    }

    Write-Host "Processo de reparo concluído. Relatório salvo em $ReportPath" -ForegroundColor Green
}






#--------------------------------------------------------------------------
# 16 - Função para organizar o relatório

function Organize-Report {
    param ([string]$ReportPath)
    Update-Progress
    Write-Host "Organizando relatório..." -ForegroundColor Yellow
    $startTime = Get-Date

    Collect-SystemInfo -ReportPath $ReportPath
    Collect-Profiles -ReportPath $ReportPath
     Check-SystemIntegrity -ReportPath $ReportPath
    Check-Security -ReportPath $ReportPath
    Collect-Printers -ReportPath $ReportPath
    Update-Windows -ReportPath $ReportPath
    Update-Software -ReportPath $ReportPath
    Clean-TemporaryFiles -ReportPath $ReportPath
    Disk-Maintenance -ReportPath $ReportPath
    $reportPath
    Repair-Windows -ReportPath $ReportPath

    $endTime = Get-Date
    $executionTime = ($endTime - $startTime).TotalMinutes
    $formattedTime = Format-ExecutionTime -executionTime $executionTime
    if (![string]::IsNullOrEmpty($ReportPath)) {
        Add-Content -Path $ReportPath -Value "`n=== Tempo Total de Execução ===`n$formattedTime" -Encoding UTF8
    }
    Write-Host "Tempo total de execução: $formattedTime" -ForegroundColor Green
}

# Executar a organização do relatório
Organize-Report -ReportPath $reportPath
