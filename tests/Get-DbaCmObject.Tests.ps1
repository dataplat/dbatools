param($ModuleName = 'dbatools')

Describe "Get-DbaCmObject" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCmObject
        }
        It "Should have ClassName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ClassName
        }
        It "Should have Query as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Query
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Namespace as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Namespace
        }
        It "Should have DoNotUse as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DoNotUse
        }
        It "Should have Force as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have SilentlyContinue as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SilentlyContinue
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        It "returns a bias that's an int" {
            $result = Get-DbaCmObject -ClassName Win32_TimeZone
            $result.Bias | Should -BeOfType [int]
        }
    }
}
