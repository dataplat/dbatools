param($ModuleName = 'dbatools')

Describe "Get-DbaProductKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaProductKey
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
