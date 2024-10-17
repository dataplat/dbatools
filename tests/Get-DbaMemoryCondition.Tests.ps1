param($ModuleName = 'dbatools')

Describe "Get-DbaMemoryCondition" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaMemoryCondition
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

Describe "Get-DbaMemoryCondition Integration Test" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaMemoryCondition -SqlInstance $global:instance1
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Runtime', 'NotificationTime', 'NotificationType', 'MemoryUtilizationPercent', 'TotalPhysicalMemory', 'AvailablePhysicalMemory', 'TotalPageFile', 'AvailablePageFile', 'TotalVirtualAddressSpace', 'AvailableVirtualAddressSpace', 'NodeId', 'SQLReservedMemory', 'SQLCommittedMemory', 'RecordId', 'Type', 'Indicators', 'RecordTime', 'CurrentTime'
            $result.PSObject.Properties.Name | Should -Be $ExpectedProps
        }
    }
}
