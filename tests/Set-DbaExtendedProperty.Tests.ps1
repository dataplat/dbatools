param($ModuleName = 'dbatools')

Describe "Set-DbaExtendedProperty" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaExtendedProperty
        }
        $params = @(
            "InputObject",
            "Value",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Set-DbaExtendedProperty Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
        $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName
        $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value $newDbName
    }

    AfterAll {
        $null = $db | Remove-DbaDatabase
    }

    Context "commands work as expected" {
        It "works" {
            $ep = Get-DbaExtendedProperty -SqlInstance $instance2 -Name "Test_Database_Name"
            $newep = $ep | Set-DbaExtendedProperty -Value "Test_Database_Value"
            $newep.Name | Should -Be "Test_Database_Name"
            $newep.Value | Should -Be "Test_Database_Value"
        }
    }
}
