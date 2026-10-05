#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaNetworkCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "EnableException"
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
    BeforeAll {
        # The command runs in a runspace of its own, created by the PowerShell API without a host. There
        # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
        # as an Id whose last record is not a completed one. Select-Object -First 1 stops the command at
        # its result. Removing the certificate setting needs no restart to be undone: a certificate that
        # was configured is put back in the AfterAll. The runspace imports the manifest: an import of the
        # psm1 without a command line skips the type data.
        $splatFirstRemoval = @{
            SqlInstance = $TestConfig.InstanceRestart
            Confirm     = $false
        }
        $removeRunspace = [runspacefactory]::CreateRunspace()
        $removeRunspace.Open()
        $importShell = [powershell]::Create()
        $importShell.Runspace = $removeRunspace
        $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
        $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
        $importShell.Dispose()

        $removeShell = [powershell]::Create()
        $removeShell.Runspace = $removeRunspace
        $firstRemoval = $removeShell.AddCommand("Remove-DbaNetworkCertificate").AddParameters($splatFirstRemoval).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
        $removeRecords = @($removeShell.Streams.Progress)
        $removeShell.Dispose()
        $removeRunspace.Dispose()
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($firstRemoval.RemovedThumbprint) {
            $null = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -Thumbprint $firstRemoval.RemovedThumbprint
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When the pipeline ends at the result" {
        It "Returns the result of the instance" {
            $firstRemoval.InstanceName | Should -Not -BeNullOrEmpty
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $removeRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $removeRecords | Where-Object Activity -eq "Executing Remove-DbaNetworkCertificate" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}