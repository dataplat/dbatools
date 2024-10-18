param($ModuleName = 'dbatools')

Describe "New-DbaScriptingOption" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaScriptingOption
        }
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory -Alias 'ConnectionString'
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
            # Add more parameter checks as needed
        }
    }

    Context "Functional tests" {
        BeforeAll {
            # Add any setup code here
        }

        It "Creates a new scripting option object" {
            $result = New-DbaScriptingOption
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ScriptingOptions]
        }

        # Add more functional tests as needed
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
