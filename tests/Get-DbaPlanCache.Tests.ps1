param($ModuleName = 'dbatools')

Describe "Get-DbaPlanCache" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPlanCache
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
        }

        It "returns correct datatypes" {
            $results = Get-DbaPlanCache -SqlInstance $global:instance1 | Clear-DbaPlanCache -Threshold 1024
            $results.Size | Should -BeOfType [dbasize]
        }
    }
}
