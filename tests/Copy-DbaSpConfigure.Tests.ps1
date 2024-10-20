param($ModuleName = 'dbatools')

Describe "Copy-DbaSpConfigure" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaSpConfigure
        }
        $parms = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'ConfigName',
            'ExcludeConfigName',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Copy config with the same properties" -Tag "IntegrationTests" {
        BeforeAll {
            $global:sourceconfig = (Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $global:destconfig = (Get-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout).ConfiguredValue
            # Set it so they don't match
            if ($global:sourceconfig -and $global:destconfig) {
                $newvalue = $global:sourceconfig + $global:destconfig
                $null = Set-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout -Value $newvalue
            }
        }

        AfterAll {
            if ($global:destconfig -and $global:destconfig -ne $global:sourceconfig) {
                $null = Set-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName RemoteQueryTimeout -Value $global:destconfig
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
            $newconfig | Should -Be $global:sourceconfig
        }
    }
}
