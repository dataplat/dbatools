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
        It "Should have Path as a non-mandatory parameter of type FileInfo" {
            $CommandUnderTest | Should -HaveParameter Path -Type Microsoft.SqlServer.Management.Smo.FileInfo -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
