#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = [System.IO.Path]::GetFileName($PSCommandPath.Replace('.Tests.ps1', '')),
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Add-DbaExtendedProperty" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
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

Describe "Add-DbaExtendedProperty" -Tag "IntegrationTests" {
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
