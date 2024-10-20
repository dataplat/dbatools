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
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Spid",
            "ExcludeSpid",
            "Database",
            "Login",
            "Hostname",
            "Program",
            "ExcludeSystemSpids",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
