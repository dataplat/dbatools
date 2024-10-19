param($ModuleName = 'dbatools')

Describe "Get-DbaDbccProcCache" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccProcCache
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
