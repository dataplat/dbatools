param($ModuleName = 'dbatools')

Describe "Find-DbaCommand" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaCommand
        }
        It "Should have Pattern as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type System.String -Mandatory:$false
        }
        It "Should have Tag as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Tag -Type System.String[] -Mandatory:$false
        }
        It "Should have Author as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Author -Type System.String -Mandatory:$false
        }
        It "Should have MinimumVersion as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumVersion -Type System.String -Mandatory:$false
        }
        It "Should have MaximumVersion as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter MaximumVersion -Type System.String -Mandatory:$false
        }
        It "Should have Rebuild as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Rebuild -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command finds jobs using all parameters" {
        It "Should find more than 5 snapshot commands" {
            $results = Find-DbaCommand -Pattern "snapshot"
            $results.Count | Should -BeGreaterThan 5
        }

        It "Should find more than 20 commands tagged as job" {
            $results = Find-DbaCommand -Tag Job
            $results.Count | Should -BeGreaterThan 20
        }

        It "Should find a command that has both Job and Owner tags" {
            $results = Find-DbaCommand -Tag Job, Owner
            $results.CommandName | Should -Contain "Test-DbaAgentJobOwner"
        }

        It "Should find more than 250 commands authored by Chrissy" {
            $results = Find-DbaCommand -Author chrissy
            $results.Count | Should -BeGreaterThan 250
        }

        It "Should find more than 15 commands for AGs authored by Chrissy" {
            $results = Find-DbaCommand -Author chrissy -Tag AG
            $results.Count | Should -BeGreaterThan 15
        }

        It "Should find more than 5 snapshot commands after Rebuilding the index" {
            $results = Find-DbaCommand -Pattern snapshot -Rebuild
            $results.Count | Should -BeGreaterThan 5
        }
    }
}
