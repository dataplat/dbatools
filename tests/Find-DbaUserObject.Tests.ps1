param($ModuleName = 'dbatools')

Describe "Find-DbaUserObject" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaUserObject
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command finds User Objects for SA" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_userObject' -Owner 'sa'
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database 'dbatoolsci_userObject' -Confirm:$false
        }

        It "Should find a specific Database Owned by sa" {
            $results = Find-DbaUserObject -SqlInstance $global:instance2 -Pattern sa
            $results.Where( {$_.name -eq 'dbatoolsci_userobject'}).Type | Should -Be "Database"
        }
        It "Should find more than 10 objects Owned by sa" {
            $results = Find-DbaUserObject -SqlInstance $global:instance2 -Pattern sa
            $results.Count | Should -BeGreaterThan 10
        }
    }

    Context "Command finds User Objects" {
        It "Should find results" {
            $results = Find-DbaUserObject -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
