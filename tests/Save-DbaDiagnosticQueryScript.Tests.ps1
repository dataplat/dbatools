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
        $params = @(
            "SqlInstance",
            "SqlCredential"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
