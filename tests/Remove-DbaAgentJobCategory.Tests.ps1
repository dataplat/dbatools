param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentJobCategory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentJobCategory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Category as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Category -Type System.String[] -Mandatory:$false
        }
        It "Should have CategoryType as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter CategoryType -Type System.String[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Agent.JobCategory[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Agent.JobCategory[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

Describe "Remove-DbaAgentJobCategory Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "New Agent Job Category is changed properly" {
        BeforeAll {
            $results = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
        }

        It "Should have the right name and category type" {
            $results[0].Name | Should -Be "CategoryTest1"
            $results[0].CategoryType | Should -Be "LocalJob"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[1].CategoryType | Should -Be "LocalJob"
            $results[2].Name | Should -Be "CategoryTest3"
            $results[2].CategoryType | Should -Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3
            $newresults.Count | Should -Be 3
        }

        It "Remove the job categories" {
            Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, Categorytest3 -Confirm:$false

            $newresults = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3

            $newresults.Count | Should -Be 0
        }

        AfterAll {
            # Cleanup any remaining test categories
            Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1, CategoryTest2, CategoryTest3 -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
