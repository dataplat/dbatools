param($ModuleName = 'dbatools')

Describe "Export-DbaReplServerSetting" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaReplServerSetting
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have FilePath as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have ScriptOption as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptOption
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Encoding as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding
        }
        It "Should have Passthru as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru
        }
        It "Should have NoClobber as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber
        }
        It "Should have Append as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Append
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
