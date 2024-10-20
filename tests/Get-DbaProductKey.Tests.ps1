param($ModuleName = 'dbatools')

Describe "Get-DbaProductKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaProductKey
        }

        $params = @(
            "ComputerName",
            "SqlCredential",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Gets ProductKey for Instances on $env:ComputerName" {
            BeforeAll {
                $results = Get-DbaProductKey -ComputerName $env:ComputerName
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have Version, Edition, and Key for each result" {
                foreach ($row in $results) {
                    $row.Version | Should -Not -BeNullOrEmpty
                    $row.Edition | Should -Not -BeNullOrEmpty
                    $row.Key | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
}
