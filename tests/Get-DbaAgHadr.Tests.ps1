param($ModuleName = 'dbatools')

Describe "Get-DbaAgHadr" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgHadr
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" -Skip:(-not $env:APPVEYOR) {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance3
        }

        It "returns the correct properties" {
            $results = Get-DbaAgHadr -SqlInstance $global:instance3
            $results.IsHadrEnabled | Should -Be $true
        }
    }
}
