#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipRecovery",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "NoRecovery",
                "EnableException",
                "Force",
                "InputObject",
                "Delay"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When the database is not a log shipping secondary" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id with records but without a completed one. master is never a log shipping secondary, so
            # the command draws its bar, warns and moves on to the next database without changing anything.
            # The runspace imports the manifest: an import of the psm1 without a command line skips the type data.
            $splatRecovery = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
            }
            if ($TestConfig.SqlCred) {
                $splatRecovery.SqlCredential = $TestConfig.SqlCred
            }
            $recoveryRunspace = [runspacefactory]::CreateRunspace()
            $recoveryRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $recoveryRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $recoveryShell = [powershell]::Create()
            $recoveryShell.Runspace = $recoveryRunspace
            $null = $recoveryShell.AddCommand("Invoke-DbaDbLogShipRecovery").AddParameters($splatRecovery).Invoke()
            $recoveryWarnings = @($recoveryShell.Streams.Warning | ForEach-Object { $PSItem.Message })
            $recoveryRecords = @($recoveryShell.Streams.Progress)
            $recoveryShell.Dispose()
            $recoveryRunspace.Dispose()
        }

        It "Warns that the database is not a log shipping secondary" {
            ($recoveryWarnings -join " ") | Should -Match "is not configured as a secondary database for log shipping"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $recoveryRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $recoveryRecords | Where-Object Activity -like "Performing log shipping recovery*" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}