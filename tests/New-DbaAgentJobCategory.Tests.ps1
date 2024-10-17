param($ModuleName = 'dbatools')

Describe "New-DbaAgentJobCategory" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentJobCategory
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Category parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type String[]
        }
        It "Should have CategoryType parameter" {
            $CommandUnderTest | Should -HaveParameter CategoryType -Type String
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "New Agent Job Category is added properly" {
        BeforeAll {
            $env:instance2 = "localhost"
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $env:instance2 -Category CategoryTest1
            $results.Name | Should -Be "CategoryTest1"
            $results.CategoryType | Should -Be "LocalJob"
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $env:instance2 -Category CategoryTest2 -CategoryType MultiServerJob
            $results.Name | Should -Be "CategoryTest2"
            $results.CategoryType | Should -Be "MultiServerJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $env:instance2 -Category CategoryTest1, CategoryTest2
            $newresults[0].Name | Should -Be "CategoryTest1"
            $newresults[0].CategoryType | Should -Be "LocalJob"
            $newresults[1].Name | Should -Be "CategoryTest2"
            $newresults[1].CategoryType | Should -Be "MultiServerJob"
        }

        It "Should not write over existing job categories" {
            $warn = $null
            $results = New-DbaAgentJobCategory -SqlInstance $env:instance2 -Category CategoryTest1 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "already exists"
        }

        AfterAll {
            # Cleanup and ignore all output
            Remove-DbaAgentJobCategory -SqlInstance $env:instance2 -Category CategoryTest1, CategoryTest2 -Confirm:$false *> $null
        }
    }
}
