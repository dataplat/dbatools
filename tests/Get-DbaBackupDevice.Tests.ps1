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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $sql = "EXEC sp_addumpdevice 'tape', 'dbatoolsci_tape', '\\.\tape0';"
        $server.Query($sql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $sql = "EXEC sp_dropdevice 'dbatoolsci_tape';"
        $server.Query($sql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets the backup devices" {
        BeforeAll {
            $results = Get-DbaBackupDevice -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.BackupDevice]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "BackupDeviceType",
                "PhysicalLocation",
                "SkipTapeLabel"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.BackupDevice"
        }
    }
}