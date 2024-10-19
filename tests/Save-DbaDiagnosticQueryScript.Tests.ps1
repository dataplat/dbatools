param($ModuleName = 'dbatools')

Describe "Save-DbaDiagnosticQueryScript" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Save-DbaDiagnosticQueryScript
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Path",
                "EnableException",
                "SqlInstance",
                "SqlCredential"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    # Add more contexts and tests as needed for integration testing
    # For example:
    # Context "Integration Tests" {
    #     It "Should save the diagnostic query script" {
    #         # Test implementation
    #     }
    # }
}
