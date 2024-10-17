param($ModuleName = 'dbatools')
Describe "Set-DbaAgentJobCategory" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJobCategory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Category as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[] -Not -Mandatory
        }
        It "Should have NewName as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter NewName -Type String[] -Not -Mandatory
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "New Agent Job Category is changed properly" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
        }

        AfterAll {
            Remove-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest2 -Confirm:$false
        }

        It "Should create a new job category with the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1
            $results.Name | Should -Be "CategoryTest1"
            $results.CategoryType | Should -Be "LocalJob"
        }

        It "Should verify the newly created job category exists" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1
            $newresults.Name | Should -Be "CategoryTest1"
            $newresults.CategoryType | Should -Be "LocalJob"
        }

        It "Should change the name of the job category" {
            $results = Set-DbaAgentJobCategory -SqlInstance $global:instance2 -Category CategoryTest1 -NewName CategoryTest2
            $results.Name | Should -Be "CategoryTest2"
        }
    }
}
