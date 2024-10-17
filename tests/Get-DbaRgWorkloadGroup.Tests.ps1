param($ModuleName = 'dbatools')

Describe "Get-DbaRgWorkloadGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgWorkloadGroup
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type ResourcePool[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type ResourcePool[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Connects and retrieves workload groups" -ForEach $global:instance1, $global:instance2 {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $_
            }

            It "Should retrieve workload groups from the server" {
                $results = Get-DbaRgWorkloadGroup -SqlInstance $server
                $results | Should -Not -BeNullOrEmpty
                $results | Should -BeOfType [PSCustomObject]
                $results.SqlInstance | Should -Be $server.Name
            }

            It "Should have the correct properties" {
                $results = Get-DbaRgWorkloadGroup -SqlInstance $server
                $results | Should -HaveProperty 'ComputerName'
                $results | Should -HaveProperty 'InstanceName'
                $results | Should -HaveProperty 'SqlInstance'
                $results | Should -HaveProperty 'ResourcePool'
                $results | Should -HaveProperty 'Name'
            }
        }

        Context "Handles pipeline input" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $global:instance1
                $resourcePools = Get-DbaRgResourcePool -SqlInstance $server
            }

            It "Should accept pipeline input" {
                $results = $resourcePools | Get-DbaRgWorkloadGroup
                $results | Should -Not -BeNullOrEmpty
                $results | Should -BeOfType [PSCustomObject]
                $results.SqlInstance | Should -Be $server.Name
            }
        }

        Context "Handles errors gracefully" {
            It "Should not throw an exception when EnableException is not used" {
                { Get-DbaRgWorkloadGroup -SqlInstance 'InvalidInstance' } | Should -Not -Throw
            }

            It "Should throw an exception when EnableException is used" {
                { Get-DbaRgWorkloadGroup -SqlInstance 'InvalidInstance' -EnableException } | Should -Throw
            }
        }
    }
}
