#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbBackupRestoreHistory",
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
                "KeepDays",
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe $CommandName -Tag IntegrationTests {
    # Characterization context (W1-094 law: an empty run is never green). Scoped to a
    # throwaway database's own backup history so nothing else in msdb is touched.
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $historyDbName = "dbatoolsci_history_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $historyDbName
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $historyDbName -Path $backupPath

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $historyDbName -ErrorAction SilentlyContinue
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing backup history for a database" {
        It "Removes the database's backup history" {
            $before = @(Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $historyDbName)
            $before.Count | Should -BeGreaterThan 0

            $null = Remove-DbaDbBackupRestoreHistory -SqlInstance $TestConfig.InstanceSingle -Database $historyDbName -Confirm:$false

            $after = @(Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $historyDbName)
            $after.Count | Should -Be 0
        }
    }
}