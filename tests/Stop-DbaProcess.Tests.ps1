param($ModuleName = 'dbatools')

Describe "Stop-DbaProcess" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaProcess
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Spid",
                "ExcludeSpid",
                "Database",
                "Login",
                "Hostname",
                "Program",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command works as expected" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
        }

        It "Kills only this specific process" {
            $fakeapp = Connect-DbaInstance -SqlInstance $global:instance1 -ClientName 'dbatoolsci test app'
            $results = Stop-DbaProcess -SqlInstance $global:instance1 -Program 'dbatoolsci test app'
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }

        It "Supports piping" {
            $fakeapp = Connect-DbaInstance -SqlInstance $global:instance1 -ClientName 'dbatoolsci test app'
            $results = Get-DbaProcess -SqlInstance $global:instance1 -Program 'dbatoolsci test app' | Stop-DbaProcess
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }
    }
}
