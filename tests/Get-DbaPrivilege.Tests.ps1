param($ModuleName = 'dbatools')

Describe "Get-DbaPrivilege" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPrivilege
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
