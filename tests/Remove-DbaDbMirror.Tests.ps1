#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMirror",
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
                "Database",
                "InputObject",
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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # A mirroring session between the two copy instances, to be removed by the test
        $dbName = "dbatoolsci_removemirror"
        $endpointName = "dbatoolsci_MirroringEndpoint"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $dbName
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1 -Name $endpointName -Type DatabaseMirroring -Port 5022 -Owner sa
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Name $endpointName -Type DatabaseMirroring -Port 5023 -Owner sa
        $splatMirroring = @{
            Primary    = $TestConfig.InstanceCopy1
            Mirror     = $TestConfig.InstanceCopy2
            Database   = $dbName
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        $null = Invoke-DbaDbMirroring @splatMirroring

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -EndPoint $endpointName

        # Seeding the mirror leaves the full backup and the log backup in the shared folder.
        Get-ChildItem -Path $TestConfig.Temp -Filter "$dbName*" | Remove-Item -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing the mirror from the mirror database" {
        BeforeAll {
            # Removed from the mirror side, whose database is restoring. SMO turns the partner off there as well, so the
            # T-SQL fallback for a failing Alter() is not reached here.
            $results = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceCopy2 -Database $dbName
        }

        It "Returns one result" {
            # Counts the output itself, $results.Status would skip a $null written by the command
            @($results).Count | Should -Be 1
            $results.Status | Should -Be "Removed"
        }

        It "Ends the mirroring session" {
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $dbName).IsMirroringEnabled | Should -BeFalse
        }
    }
}