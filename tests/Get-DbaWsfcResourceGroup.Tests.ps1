param($ModuleName = 'dbatools')

Describe "Get-DbaWsfcResourceGroup" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWsfcResourceGroup
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Name as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}
