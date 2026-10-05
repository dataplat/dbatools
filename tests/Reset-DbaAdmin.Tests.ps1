#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Reset-DbaAdmin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "SecurePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because command is not supported.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceRestart -Login dbatoolsci_resetadmin | Stop-DbaProcess -WarningAction SilentlyContinue
        Get-DbaLogin -SqlInstance $TestConfig.InstanceRestart -Login dbatoolsci_resetadmin | Remove-DbaLogin

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a sql login" {
        BeforeAll {
            # The reset runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. Select-Object -First 1 stops the command at
            # its only output, the login, so the same restart also shows whether the bar survives a pipeline
            # that ends early. The runspace imports the manifest: an import of the psm1 without a command
            # line skips the type data.
            $password = ConvertTo-SecureString -Force -AsPlainText resetadmin1
            $splatReset = @{
                SqlInstance    = $TestConfig.InstanceRestart
                Login          = "dbatoolsci_resetadmin"
                SecurePassword = $password
                Confirm        = $false
            }
            if ($TestConfig.SqlCred) {
                $splatReset.SqlCredential = $TestConfig.SqlCred
            }
            $resetRunspace = [runspacefactory]::CreateRunspace()
            $resetRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $resetRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $resetShell = [powershell]::Create()
            $resetShell.Runspace = $resetRunspace
            $results = $resetShell.AddCommand("Reset-DbaAdmin").AddParameters($splatReset).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
            $resetRecords = @($resetShell.Streams.Progress)
            $resetShell.Dispose()
            $resetRunspace.Dispose()
        }

        It "Should add the login as sysadmin" {
            $results.Name | Should -Be dbatoolsci_resetadmin
            $results.IsMember("sysadmin") | Should -Be $true
        }

        It "Completes its progress bar when the pipeline ends at the login" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $resetRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $resetRecords | Where-Object Activity -eq "Executing Reset-DbaAdmin" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}