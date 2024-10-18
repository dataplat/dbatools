param($ModuleName = 'dbatools')

Describe "New-DbaAgentAlertCategory" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentAlertCategory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Category as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[] -Mandatory:$false
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "New Agent Alert Category is added properly" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        AfterAll {
            # Cleanup and ignore all output
            $null = Remove-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2 -Confirm:$false
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1
            $results.Name | Should -Be "CategoryTest1"
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest2
            $results.Name | Should -Be "CategoryTest2"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2
            $newresults[0].Name | Should -Be "CategoryTest1"
            $newresults[1].Name | Should -Be "CategoryTest2"
        }

        It "Should not write over existing job categories" {
            $warn = $null
            $results = New-DbaAgentAlertCategory -SqlInstance $global:instance2 -Category CategoryTest1 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "already exists"
        }
    }
}
