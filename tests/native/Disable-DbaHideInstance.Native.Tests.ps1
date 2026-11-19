#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database is a managed database service and exposes no Windows SQL Server Browser registry to change instance discovery. https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaHideInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Disable-DbaHideInstance" -Tag IntegrationTests {
    BeforeAll {
        $nativeHidingInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeHidingComputer = $nativeHidingInstance.ComputerName
        $nativeHidingInstanceName = $nativeHidingInstance.InstanceName
        $nativeHidingSession = New-PSSession -ComputerName $nativeHidingComputer -ErrorAction Stop
        $nativeHidingState = Invoke-Command -Session $nativeHidingSession -ArgumentList $nativeHidingInstanceName -ErrorAction Stop -ScriptBlock {
            param($instanceName)
            $instanceMap = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop
            $instanceId = $instanceMap.$instanceName
            if (-not $instanceId) { throw 'Missing SQL instance registry mapping.' }
            $key = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib"
            $values = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            [pscustomobject]@{ Key = $key; Value = $values.HideInstance; ComputerName = $env:COMPUTERNAME }
        }
        $nativeHidingState.Value | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        if ($nativeHidingSession) {
            try {
                if ($nativeHidingState) {
                    Invoke-Command -Session $nativeHidingSession -ArgumentList $nativeHidingState.Key, $nativeHidingState.Value -ErrorAction Stop -ScriptBlock {
                        param($key, $value)
                        Set-ItemProperty -LiteralPath $key -Name HideInstance -Value $value -ErrorAction Stop
                    }
                }
            } finally {
                Remove-PSSession -Session $nativeHidingSession
            }
        }
    }

    BeforeEach {
        Invoke-Command -Session $nativeHidingSession -ArgumentList $nativeHidingState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            Set-ItemProperty -LiteralPath $key -Name HideInstance -Value 1 -ErrorAction Stop
        }
    }

    AfterEach {
        Invoke-Command -Session $nativeHidingSession -ArgumentList $nativeHidingState.Key, $nativeHidingState.Value -ErrorAction Stop -ScriptBlock {
            param($key, $value)
            Set-ItemProperty -LiteralPath $key -Name HideInstance -Value $value -ErrorAction Stop
        }
    }

    It "disables hiding and returns the target identity" -Tag "NativeChecklist:switch-false" {
        $nativeHidingOutput = @(Disable-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle -WhatIf:$false -Confirm:$false -EnableException)
        $nativeHidingOutput.Count | Should -Be 1
        $nativeHidingOutput[0].HideInstance | Should -BeFalse
        $nativeHidingOutput[0].ComputerName | Should -BeExactly $nativeHidingState.ComputerName
        $nativeHidingOutput[0].InstanceName | Should -BeExactly $nativeHidingInstanceName
        $nativeHidingOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        $readback = Invoke-Command -Session $nativeHidingSession -ArgumentList $nativeHidingState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            (Get-ItemProperty -LiteralPath $key -Name HideInstance -ErrorAction Stop).HideInstance
        }
        $readback | Should -Be 0
    }

    It "leaves the registry unchanged under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        @(Disable-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle -WhatIf -Confirm:$false -EnableException).Count | Should -Be 0
        $readback = Invoke-Command -Session $nativeHidingSession -ArgumentList $nativeHidingState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            (Get-ItemProperty -LiteralPath $key -Name HideInstance -ErrorAction Stop).HideInstance
        }
        $readback | Should -Be 1
    }

    It "ignores a supplied credential for local registry access in this PowerShell edition" {
        $localRegistryRoot = 'SOFTWARE\dbatoolsNativeTests\' + [guid]::NewGuid().ToString('N')
        $localRegistryPath = 'HKLM:\' + $localRegistryRoot
        $localNetworkPath = $localRegistryPath + '\MSSQLServer\SuperSocketNetLib'
        $unusedCredential = New-Object System.Management.Automation.PSCredential ('native-unused-user', (ConvertTo-SecureString 'native-unused-password' -AsPlainText -Force))
        try {
            $null = New-Item -Path $localNetworkPath -Force -ErrorAction Stop
            $null = New-ItemProperty -LiteralPath $localNetworkPath -Name HideInstance -PropertyType DWord -Value 1 -ErrorAction Stop
            $localResult = [Dataplat.Dbatools.Commands.ForceEncryptionResolver]::SetNetworkFlag($env:COMPUTERNAME, $localRegistryRoot, 'HideInstance', 0, $unusedCredential, $false)
            $localResult.Value | Should -Be 0
            (Get-ItemProperty -LiteralPath $localNetworkPath -Name HideInstance -ErrorAction Stop).HideInstance | Should -Be 0
        } finally {
            if (Test-Path -LiteralPath $localRegistryPath) {
                Remove-Item -LiteralPath $localRegistryPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    It "disables the local SQL instance with a supplied credential and verifies registry readback" {
        # The claimed SQL host runs Windows PowerShell; the separate local-registry case exercises each runner edition.
        $localCommandRoot = 'C:\native\hide-local-' + [guid]::NewGuid().ToString('N')
        $localCommandPayload = $localCommandRoot + '\payload'
        $localCommandSession = $null
        try {
            $null = Invoke-Command -Session $nativeHidingSession -ArgumentList $localCommandRoot -ErrorAction Stop -ScriptBlock {
                param($root)
                foreach ($previous in Get-ChildItem -LiteralPath 'C:\native' -Directory -Filter 'hide-local-*' -ErrorAction Stop) {
                    if ($previous.Name -notmatch '^hide-local-[a-f0-9]{32}$') { continue }
                    if (-not (Test-Path -LiteralPath (Join-Path $previous.FullName '.native-session-closed'))) { continue }
                    try { Remove-Item -LiteralPath $previous.FullName -Recurse -Force -ErrorAction Stop }
                    catch {
                        Write-Warning "Retaining completed native test payload $($previous.FullName): $($_.Exception.Message)"
                        try { Set-Content -LiteralPath (Join-Path $previous.FullName '.native-session-closed') -Value 'The command session has closed.' -ErrorAction Stop }
                        catch { Write-Warning "Could not retain the completed-payload marker: $($_.Exception.Message)" }
                    }
                }
                New-Item -ItemType Directory -Path $root -ErrorAction Stop
            }
            $nativeModuleRoot = (Get-Module -Name $ModuleName -ErrorAction Stop).ModuleBase
            Copy-Item -LiteralPath $nativeModuleRoot -Destination $localCommandPayload -ToSession $nativeHidingSession -Recurse -Force -ErrorAction Stop
            $localCommandSession = New-PSSession -ComputerName $nativeHidingComputer -ErrorAction Stop
            $localCommandResult = Invoke-Command -Session $localCommandSession -ArgumentList $localCommandPayload, $nativeHidingInstanceName, $nativeHidingState.Key -ErrorAction Stop -ScriptBlock {
                param($payload, $instanceName, $key)
                Import-Module ($payload + '\dbatools.psd1') -Force -ErrorAction Stop
                $original = (Get-ItemProperty -LiteralPath $key -Name HideInstance -ErrorAction Stop).HideInstance
                $unusedCredential = New-Object System.Management.Automation.PSCredential ('native-unused-user', (ConvertTo-SecureString 'native-unused-password' -AsPlainText -Force))
                try {
                    $target = $env:COMPUTERNAME
                    if ($instanceName -ne 'MSSQLSERVER') { $target += '\' + $instanceName }
                    $output = @(Disable-DbaHideInstance -SqlInstance $target -Credential $unusedCredential -Confirm:$false -EnableException)
                    [pscustomobject]@{
                        Count = $output.Count
                        Hidden = $output[0].HideInstance
                        ComputerName = $output[0].ComputerName
                        InstanceName = $output[0].InstanceName
                        Readback = (Get-ItemProperty -LiteralPath $key -Name HideInstance -ErrorAction Stop).HideInstance
                    }
                } finally {
                    Set-ItemProperty -LiteralPath $key -Name HideInstance -Value $original -ErrorAction Stop
                }
            }
            $localCommandResult.Count | Should -Be 1
            $localCommandResult.Hidden | Should -BeFalse
            $localCommandResult.ComputerName | Should -BeExactly $nativeHidingState.ComputerName
            $localCommandResult.InstanceName | Should -BeExactly $nativeHidingInstanceName
            $localCommandResult.Readback | Should -Be 0
        } finally {
            if ($localCommandSession) { Remove-PSSession -Session $localCommandSession }
            Invoke-Command -Session $nativeHidingSession -ArgumentList $localCommandRoot -ErrorAction Stop -ScriptBlock {
                param($root)
                # The registry assertions and restoration stay strict; loaded DLL cleanup is best-effort.
                try {
                    if (Test-Path -LiteralPath $root) {
                        Set-Content -LiteralPath (Join-Path $root '.native-session-closed') -Value 'The command session has closed.' -ErrorAction Stop
                        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
                    }
                } catch {
                    Write-Warning "Retaining completed native test payload ${root}: $($_.Exception.Message)"
                    try { Set-Content -LiteralPath (Join-Path $root '.native-session-closed') -Value 'The command session has closed.' -ErrorAction Stop }
                    catch { Write-Warning "Could not retain the completed-payload marker: $($_.Exception.Message)" }
                }
            }
        }
    }

    It "continues around a missing middle service and preserves both output records" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $missingHidingInstance = $nativeHidingComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nativeHidingWarnings = @()
        $nativeHidingOutput = @(@($TestConfig.InstanceSingle, $missingHidingInstance, $TestConfig.InstanceSingle) | Disable-DbaHideInstance -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeHidingWarnings)
        $nativeHidingOutput.Count | Should -Be 2
        $nativeHidingOutput[0].HideInstance | Should -BeFalse
        $nativeHidingOutput[1].HideInstance | Should -BeFalse
        ($nativeHidingWarnings -join ' ') | Should -BeLike "*Can't find instance*"
    }

    It "retains earlier output before EnableException terminates on a missing service" -Tag "NativeChecklist:enable-exception" {
        $missingHidingInstance = $nativeHidingComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nativeHidingSeen = New-Object System.Collections.ArrayList
        $nativeHidingError = $null
        try {
            @($TestConfig.InstanceSingle, $missingHidingInstance, $TestConfig.InstanceSingle) | Disable-DbaHideInstance -Confirm:$false -EnableException | ForEach-Object { $null = $nativeHidingSeen.Add($_) }
        } catch {
            $nativeHidingError = $_
        }
        $nativeHidingSeen.Count | Should -Be 1
        $nativeHidingError | Should -Not -BeNullOrEmpty
        $nativeHidingError.CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }

    It "does not default explicit null or empty instance input to the local machine" {
        @(Disable-DbaHideInstance -SqlInstance $null -Confirm:$false -EnableException).Count | Should -Be 0
        @(Disable-DbaHideInstance -SqlInstance @() -Confirm:$false -EnableException).Count | Should -Be 0
    }
}
