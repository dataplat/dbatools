param($ModuleName = 'dbatools')

Describe "Remove-DbaExtendedProperty" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaExtendedProperty
        }
        It "Accepts InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Accepts WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable
        }
        It "Accepts InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable
        }
        It "Accepts OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable
        }
        It "Accepts OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer
        }
        It "Accepts PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable
        }
        It "Accepts WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Accepts Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }

    Context "Command usage" {
        BeforeAll {
            $random = Get-Random
            $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess
            $newDbName = "dbatoolsci_newdb_$random"
            $db = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName
        }

        AfterAll {
            $null = $db | Remove-DbaDatabase
        }

        It "removes an extended property" {
            $ep = $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value $newDbName
            $results = $ep | Remove-DbaExtendedProperty
            $results.Name | Should -Be "Test_Database_Name"
            $results.Status | Should -Be "Dropped"
        }
    }
}
