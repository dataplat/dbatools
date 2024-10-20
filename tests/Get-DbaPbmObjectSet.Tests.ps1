param($ModuleName = 'dbatools')

Describe "Get-DbaPbmObjectSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmObjectSet
        }
        It "has the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "ObjectSet",
                "InputObject",
                "IncludeSystemObject",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        # Add your integration tests here
        # Example:
        # It "Should return object sets" {
        #     $results = Get-DbaPbmObjectSet -SqlInstance $global:instance1
        #     $results | Should -Not -BeNullOrEmpty
        # }
    }
}
