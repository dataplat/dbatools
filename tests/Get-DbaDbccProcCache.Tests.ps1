param($ModuleName = 'dbatools')

Describe "Get-DbaDbccProcCache" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccProcCache
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Count', 'Used', 'Active', 'CacheSize', 'CacheUsed', 'CacheActive'
            $result = Get-DbaDbccProcCache -SqlInstance $global:instance2
        }

        It "Should return property: <_>" -ForEach $props {
            $result[0].PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }

        It "Should return results for DBCC PROCCACHE" {
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
