#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential.
# NativeChecklist: sql2005 N/A -- this command changes Windows registry settings through SQL WMI, without opening a SQL Server connection.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database enforces encrypted connections and exposes no Windows SQL service registry to configure encryption. https://learn.microsoft.com/azure/azure-sql/database/security-overview
param(
    $ModuleName = "dbatools",
    $CommandName = "Enable-DbaForceNetworkEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Enable-DbaForceNetworkEncryption" -Tag IntegrationTests {
    BeforeAll {
        $nativeEnableEncryptionInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeEnableEncryptionComputer = $nativeEnableEncryptionInstance.ComputerName
        $nativeEnableEncryptionInstanceName = $nativeEnableEncryptionInstance.InstanceName
        $nativeEnableEncryptionSession = New-PSSession -ComputerName $nativeEnableEncryptionComputer -ErrorAction Stop
        $nativeEnableEncryptionState = Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $nativeEnableEncryptionInstanceName -ErrorAction Stop -ScriptBlock {
            param($instanceName)
            $instanceMap = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop
            $instanceId = $instanceMap.$instanceName
            if (-not $instanceId) { throw 'Missing SQL instance registry mapping.' }
            $key = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib"
            $values = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $network = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
            $identity = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            [pscustomobject]@{ Key = $key; Value = $values.ForceEncryption; Certificate = $values.Certificate; ComputerName = $env:COMPUTERNAME; DnsSuffix = $network.DomainName; DnsHostName = $identity.DNSHostName; Domain = $identity.Domain }
        }
        $nativeEnableEncryptionState.Value | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        if ($nativeEnableEncryptionSession) {
            try {
                if ($nativeEnableEncryptionState) {
                    Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $nativeEnableEncryptionState.Key, $nativeEnableEncryptionState.Value -ErrorAction Stop -ScriptBlock {
                        param($key, $value)
                        Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value $value -ErrorAction Stop
                    }
                }
            } finally {
                Remove-PSSession -Session $nativeEnableEncryptionSession
            }
        }
    }

    BeforeEach {
        Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $nativeEnableEncryptionState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value 0 -ErrorAction Stop
        }
    }

    AfterEach {
        Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $nativeEnableEncryptionState.Key, $nativeEnableEncryptionState.Value -ErrorAction Stop -ScriptBlock {
            param($key, $value)
            Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value $value -ErrorAction Stop
        }
    }

    It "enables the registry value and returns the target identity and certificate" -Tag "NativeChecklist:switch-false" {
        $nativeEnableEncryptionOutput = @(Enable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WhatIf:$false -Confirm:$false -EnableException)
        $nativeEnableEncryptionOutput.Count | Should -Be 1
        $nativeEnableEncryptionOutput[0].ForceEncryption | Should -BeTrue
        $nativeEnableEncryptionOutput[0].ComputerName | Should -BeExactly $nativeEnableEncryptionState.ComputerName
        $nativeEnableEncryptionOutput[0].InstanceName | Should -BeExactly $nativeEnableEncryptionInstanceName
        $nativeEnableEncryptionOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        $nativeEnableEncryptionOutput[0].CertificateThumbprint | Should -Be $nativeEnableEncryptionState.Certificate
        ($nativeEnableEncryptionOutput[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'ComputerName,InstanceName,SqlInstance,ForceEncryption,CertificateThumbprint'
        $readback = Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $nativeEnableEncryptionState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            (Get-ItemProperty -LiteralPath $key -Name ForceEncryption -ErrorAction Stop).ForceEncryption
        }
        $readback | Should -Be 1
    }

    It "leaves the registry unchanged under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        @(Enable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WhatIf -Confirm:$false -EnableException).Count | Should -Be 0
        $readback = Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $nativeEnableEncryptionState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            (Get-ItemProperty -LiteralPath $key -Name ForceEncryption -ErrorAction Stop).ForceEncryption
        }
        $readback | Should -Be 0
    }

    It "ignores a supplied credential for local registry access in this PowerShell edition" {
        $localRegistryRoot = 'SOFTWARE\dbatoolsNativeTests\' + [guid]::NewGuid().ToString('N')
        $localRegistryPath = 'HKLM:\' + $localRegistryRoot
        $localNetworkPath = $localRegistryPath + '\MSSQLServer\SuperSocketNetLib'
        $unusedCredential = New-Object System.Management.Automation.PSCredential ('native-unused-user', (ConvertTo-SecureString 'native-unused-password' -AsPlainText -Force))
        try {
            $null = New-Item -Path $localNetworkPath -Force -ErrorAction Stop
            $null = New-ItemProperty -LiteralPath $localNetworkPath -Name ForceEncryption -PropertyType DWord -Value 0 -ErrorAction Stop
            $null = New-ItemProperty -LiteralPath $localNetworkPath -Name Certificate -PropertyType String -Value 'native-fixture-cert' -ErrorAction Stop
            $localResult = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::SetNetworkFlag($env:COMPUTERNAME, $localRegistryRoot, 'ForceEncryption', 1, $unusedCredential, $true)
            $localResult.Value | Should -Be 1
            $localResult.Certificate | Should -BeExactly 'native-fixture-cert'
            (Get-ItemProperty -LiteralPath $localNetworkPath -Name ForceEncryption -ErrorAction Stop).ForceEncryption | Should -Be 1
        } finally {
            if (Test-Path -LiteralPath $localRegistryPath) {
                Remove-Item -LiteralPath $localRegistryPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    It "enables the local SQL instance with a supplied credential and verifies registry readback" {
        # The claimed SQL host runs Windows PowerShell; the separate local-registry case exercises each runner edition.
        $localCommandRoot = 'C:\native\encryption-local-' + [guid]::NewGuid().ToString('N')
        $localCommandPayload = $localCommandRoot + '\payload'
        $localCommandSession = $null
        try {
            $null = Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $localCommandRoot -ErrorAction Stop -ScriptBlock {
                param($root)
                New-Item -ItemType Directory -Path $root -ErrorAction Stop
            }
            $nativeModuleRoot = (Get-Module -Name $ModuleName -ErrorAction Stop).ModuleBase
            Copy-Item -LiteralPath $nativeModuleRoot -Destination $localCommandPayload -ToSession $nativeEnableEncryptionSession -Recurse -Force -ErrorAction Stop
            $localCommandSession = New-PSSession -ComputerName $nativeEnableEncryptionComputer -ErrorAction Stop
            $localCommandResult = Invoke-Command -Session $localCommandSession -ArgumentList $localCommandPayload, $nativeEnableEncryptionInstanceName, $nativeEnableEncryptionState.Key -ErrorAction Stop -ScriptBlock {
                param($payload, $instanceName, $key)
                Import-Module ($payload + '\dbatools.psd1') -Force -ErrorAction Stop
                $original = (Get-ItemProperty -LiteralPath $key -Name ForceEncryption -ErrorAction Stop).ForceEncryption
                $unusedCredential = New-Object System.Management.Automation.PSCredential ('native-unused-user', (ConvertTo-SecureString 'native-unused-password' -AsPlainText -Force))
                try {
                    $target = $env:COMPUTERNAME
                    if ($instanceName -ne 'MSSQLSERVER') { $target += '\' + $instanceName }
                    $output = @(Enable-DbaForceNetworkEncryption -SqlInstance $target -Credential $unusedCredential -Confirm:$false -EnableException)
                    [pscustomobject]@{
                        Count = $output.Count
                        Encrypted = $output[0].ForceEncryption
                        ComputerName = $output[0].ComputerName
                        InstanceName = $output[0].InstanceName
                        Readback = (Get-ItemProperty -LiteralPath $key -Name ForceEncryption -ErrorAction Stop).ForceEncryption
                    }
                } finally {
                    Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value $original -ErrorAction Stop
                }
            }
            $localCommandResult.Count | Should -Be 1
            $localCommandResult.Encrypted | Should -BeTrue
            $localCommandResult.ComputerName | Should -BeExactly $nativeEnableEncryptionState.ComputerName
            $localCommandResult.InstanceName | Should -BeExactly $nativeEnableEncryptionInstanceName
            $localCommandResult.Readback | Should -Be 1
        } finally {
            if ($localCommandSession) { Remove-PSSession -Session $localCommandSession }
            Invoke-Command -Session $nativeEnableEncryptionSession -ArgumentList $localCommandRoot -ErrorAction Stop -ScriptBlock {
                param($root)
                # Closing the session can return before its WinRM host releases loaded assemblies.
                for ($cleanupAttempt = 1; $cleanupAttempt -le 15; $cleanupAttempt++) {
                    try {
                        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop }
                        break
                    } catch {
                        if ($cleanupAttempt -eq 15) { throw }
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
    }

    It "continues around a missing middle service and preserves both output records" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $missingEnableEncryptionInstance = $nativeEnableEncryptionComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nativeEnableEncryptionWarnings = @()
        $nativeEnableEncryptionOutput = @(@($TestConfig.InstanceSingle, $missingEnableEncryptionInstance, $TestConfig.InstanceSingle) | Enable-DbaForceNetworkEncryption -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeEnableEncryptionWarnings)
        $nativeEnableEncryptionOutput.Count | Should -Be 2
        $nativeEnableEncryptionOutput[0].ForceEncryption | Should -BeTrue
        $nativeEnableEncryptionOutput[1].ForceEncryption | Should -BeTrue
        ($nativeEnableEncryptionWarnings -join ' ') | Should -BeLike "*Can't find instance*"
    }

    It "retains earlier output before EnableException terminates on a missing service" -Tag "NativeChecklist:enable-exception" {
        $missingEnableEncryptionInstance = $nativeEnableEncryptionComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nativeEnableEncryptionSeen = New-Object System.Collections.ArrayList
        $nativeEnableEncryptionError = $null
        try {
            @($TestConfig.InstanceSingle, $missingEnableEncryptionInstance, $TestConfig.InstanceSingle) | Enable-DbaForceNetworkEncryption -Confirm:$false -EnableException | ForEach-Object { $null = $nativeEnableEncryptionSeen.Add($_) }
        } catch {
            $nativeEnableEncryptionError = $_
        }
        $nativeEnableEncryptionSeen.Count | Should -Be 1
        $nativeEnableEncryptionError | Should -Not -BeNullOrEmpty
        $nativeEnableEncryptionError.CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }

    It "does not fall back to the local machine for explicitly empty instance input" {
        @(Enable-DbaForceNetworkEncryption -SqlInstance $null -Confirm:$false -EnableException).Count | Should -Be 0
        @(Enable-DbaForceNetworkEncryption -SqlInstance @() -Confirm:$false -EnableException).Count | Should -Be 0
    }
}
