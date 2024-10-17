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
        It "Should have Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch
        }
        It "Should have Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch
        }
        It "Should have ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Should have WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Should have InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Should have ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Should have ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
        }
        It "Should have WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
        }
        It "Should have InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
        }
        It "Should have OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
        }
        It "Should have OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
        }
        It "Should have PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
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
        $instance2 = Connect-DbaInstance -SqlInstance $env:instance2
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
