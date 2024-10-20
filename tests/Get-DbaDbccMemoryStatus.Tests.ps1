param($ModuleName = 'dbatools')

Describe "Get-DbaDbccMemoryStatus" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccMemoryStatus
        }

        It "has the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'RecordSet', 'RowId', 'RecordSetId', 'Type', 'Name', 'Value', 'ValueType'
            $result = Get-DbaDbccMemoryStatus -SqlInstance $global:instance2
        }

        It "Should return property: <_>" -ForEach $props {
            $result[0].PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }

        It "Should return results for DBCC MEMORYSTATUS" {
            $result.Count | Should -BeGreaterThan 0
        }
    }
}
