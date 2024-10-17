param($ModuleName = 'dbatools')

Describe "Set-DbaExtendedProperty" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaExtendedProperty
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type ExtendedProperty[]
        }
        It "Should have Value as a parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch
        }
    }
}

Describe "Set-DbaExtendedProperty Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
        $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName
        $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value $newDbName
    }

    AfterAll {
        $null = $db | Remove-DbaDatabase -Confirm:$false
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
