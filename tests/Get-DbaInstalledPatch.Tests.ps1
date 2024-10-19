param($ModuleName = 'dbatools')

Describe "Get-DbaInstalledPatch" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstalledPatch
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        It "Returns output when run against a valid instance" {
            $result = Get-DbaInstalledPatch -ComputerName $global:instance1
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
