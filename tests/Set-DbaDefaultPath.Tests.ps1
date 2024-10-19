param($ModuleName = 'dbatools')

Describe "Set-DbaDefaultPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDefaultPath
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Type as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $results = Set-DbaDefaultPath -SqlInstance $global:instance1 -Type Backup -Path C:\temp
        }
        It "Data returns a value that contains :\" {
            $results.Data | Should -Match "\:\\"
        }
        It "Log returns a value that contains :\" {
            $results.Log | Should -Match "\:\\"
        }
        It "Backup returns a value that contains :\" {
            $results.Backup | Should -Match "\:\\"
        }
        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog | Should -Match "\:\\"
        }
    }
}
