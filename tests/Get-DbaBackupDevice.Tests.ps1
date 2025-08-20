#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaBackupDevice",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "EXEC sp_addumpdevice 'tape', 'dbatoolsci_tape', '\\.\tape0';"
        $server.Query($sql)

        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "EXEC sp_dropdevice 'dbatoolsci_tape';"
        $server.Query($sql)
    }

    Context "Gets the backup devices" {
        BeforeAll {
            $results = Get-DbaBackupDevice -SqlInstance $TestConfig.instance2
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the name dbatoolsci_tape" {
            $results.Name | Should -Be "dbatoolsci_tape"
        }

        It "Should have a BackupDeviceType of Tape" {
            $results.BackupDeviceType | Should -Be "Tape"
        }

        It "Should have a PhysicalLocation of \\.\Tape0" {
            $results.PhysicalLocation | Should -Be "\\.\Tape0"
        }
    }
}