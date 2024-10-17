param($ModuleName = 'dbatools')

Describe "Stop-DbaProcess" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaProcess
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Spid as a parameter" {
            $CommandUnderTest | Should -HaveParameter Spid -Type Int32[]
        }
        It "Should have ExcludeSpid as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSpid -Type Int32[]
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have Hostname as a parameter" {
            $CommandUnderTest | Should -HaveParameter Hostname -Type String[]
        }
        It "Should have Program as a parameter" {
            $CommandUnderTest | Should -HaveParameter Program -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command works as expected" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Kills only this specific process" {
            $fakeapp = Connect-DbaInstance -SqlInstance $env:instance1 -ClientName 'dbatoolsci test app'
            $results = Stop-DbaProcess -SqlInstance $env:instance1 -Program 'dbatoolsci test app'
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }

        It "Supports piping" {
            $fakeapp = Connect-DbaInstance -SqlInstance $env:instance1 -ClientName 'dbatoolsci test app'
            $results = Get-DbaProcess -SqlInstance $env:instance1 -Program 'dbatoolsci test app' | Stop-DbaProcess
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }
    }
}
