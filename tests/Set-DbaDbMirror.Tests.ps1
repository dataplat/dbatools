param($ModuleName = 'dbatools')

Describe "Set-DbaDbMirror" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbMirror
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Partner",
            "Witness",
            "SafetyLevel",
            "State",
            "InputObject",
            "EnableException"
        )
        foreach ($param in $params) {
            It "has the required parameter: $param" {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
