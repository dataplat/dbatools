param($ModuleName = 'dbatools')

Describe "Test-DbaReplLatency" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaReplLatency
        }

        $params = @(
            "SqlInstance",
            "Database",
            "SqlCredential",
            "PublicationName",
            "TimeToLive",
            "RetainToken",
            "DisplayTokenHistory",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaReplLatency
}
