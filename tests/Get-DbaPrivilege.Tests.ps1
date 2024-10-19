param($ModuleName = 'dbatools')

Describe "Get-DbaPrivilege" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPrivilege
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
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Gets Instance Privilege" {
            $results = Get-DbaPrivilege -ComputerName $env:ComputerName -WarningVariable warn 3> $null
            $results | Should -Not -BeNullOrEmpty
            $warn | Should -BeNullOrEmpty
        }
    }
}
