param($ModuleName = 'dbatools')

Describe "Get-DbaRgWorkloadGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgWorkloadGroup
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
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
