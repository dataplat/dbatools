param($ModuleName = 'dbatools')
Describe "Set-DbaAgentJobCategory" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJobCategory
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Category",
                "NewName",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
