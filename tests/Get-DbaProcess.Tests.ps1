param($ModuleName = 'dbatools')

Describe "Get-DbaProcess" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaProcess
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Spid as a parameter" {
            $CommandUnderTest | Should -HaveParameter Spid
        }
        It "Should have ExcludeSpid as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSpid
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have Hostname as a parameter" {
            $CommandUnderTest | Should -HaveParameter Hostname
        }
        It "Should have Program as a parameter" {
            $CommandUnderTest | Should -HaveParameter Program
        }
        It "Should have ExcludeSystemSpids as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemSpids
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Testing Get-DbaProcess results" {
        BeforeAll {
            $results = Get-DbaProcess -SqlInstance $global:instance1
        }

        It "matches self as a login at least once" {
            $matching = $results | Where-Object Login -match $env:username
            $matching.Length | Should -BeGreaterThan 0
        }

        It "returns only dbatools processes" {
            $results = Get-DbaProcess -SqlInstance $global:instance1 -Program 'dbatools PowerShell module - dbatools.io'
            $results | ForEach-Object {
                $_.Program | Should -Be 'dbatools PowerShell module - dbatools.io'
            }
        }

        It "returns only processes from master database" {
            $results = Get-DbaProcess -SqlInstance $global:instance1 -Database master
            $results | ForEach-Object {
                $_.Database | Should -Be 'master'
            }
        }
    }
}
