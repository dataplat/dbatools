#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = "Add-DbaExtendedProperty",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "Value",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = Get-DbaProcess -SqlInstance $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName
    }

    AfterAll {
        $null = $db | Remove-DbaDatabase -Confirm:$false
    }

    Context "When adding extended properties" {
        It "Adds an extended property to the database" {
            $splatExtendedProperty = @{
                Name  = "Test_Database_Name"
                Value = "Sup"
            }
            $ep = $db | Add-DbaExtendedProperty @splatExtendedProperty
            $ep.Name | Should -Be "Test_Database_Name"
            $ep.ParentName | Should -Be $db.Name
            $ep.Value | Should -Be "Sup"
        }
    }
}
