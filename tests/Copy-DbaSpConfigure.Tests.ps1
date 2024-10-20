param($ModuleName = 'dbatools')

Describe "Copy-DbaSpConfigure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaSpConfigure
        }

        $params = @(
            "Source",
            "SourceSqlCredential",
            "Destination",
            "DestinationSqlCredential",
            "ConfigName",
            "ExcludeConfigName",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Copy-DbaSpConfigure Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Copy config with the same properties" {
        BeforeAll {
            $sourceconfig = (Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $destconfig = (Get-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout).ConfiguredValue
            # Set it so they don't match
            if ($sourceconfig -and $destconfig) {
                $newvalue = $sourceconfig + $destconfig
                $null = Set-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout -Value $newvalue
            }
        }
        AfterAll {
            if ($destconfig -and $destconfig -ne $sourceconfig) {
                $null = Set-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout -Value $destconfig
            }
        }

        It "starts with different values" {
            $config1 = Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Not -Be $config2.ConfiguredValue
        }

        It "copied successfully" {
            $results = Copy-DbaSpConfigure -Source $global:instance1 -Destination $global:instance2 -ConfigName RemoteQueryTimeout
            $results.Status | Should -Be "Successful"
        }

        It "retains the same properties" {
            $config1 = Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Be $config2.ConfiguredValue
        }

        It "didn't modify the source" {
            $newconfig = (Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newconfig | Should -Be $sourceconfig
        }
    }
}
