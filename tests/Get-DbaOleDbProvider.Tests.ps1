param($ModuleName = 'dbatools')

Describe "Get-DbaOleDbProvider" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaOleDbProvider
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Provider",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Returns output when executed against <_>" -ForEach $global:instance1, $global:instance2 {
            $result = Get-DbaOleDbProvider -SqlInstance $_
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
