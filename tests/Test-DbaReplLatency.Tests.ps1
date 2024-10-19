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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "PublicationName",
                "TimeToLive",
                "RetainToken",
                "DisplayTokenHistory",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaReplLatency
}
