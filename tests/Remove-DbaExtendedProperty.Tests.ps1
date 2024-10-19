param($ModuleName = 'dbatools')

Describe "Remove-DbaExtendedProperty" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaExtendedProperty
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "InputObject",
                "EnableException",
                "WarningVariable",
                "InformationVariable",
                "OutVariable",
                "OutBuffer",
                "PipelineVariable",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
