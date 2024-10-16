param($ModuleName = 'dbatools')

Describe "Copy-DbaSpConfigure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaSpConfigure
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have ConfigName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigName -Type Object[]
        }
        It "Should have ExcludeConfigName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeConfigName -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}

Describe "Copy-DbaSpConfigure Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Copy config with the same properties" {
        BeforeAll {
            $sourceconfig = (Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $destconfig = (Get-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout).ConfiguredValue
            # Set it so they don't match
            if ($sourceconfig -and $destconfig) {
                $newvalue = $sourceconfig + $destconfig
                $null = Set-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout -Value $newvalue
            }
        }
        AfterAll {
            if ($destconfig -and $destconfig -ne $sourceconfig) {
                $null = Set-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout -Value $destconfig
            }
        }

        It "starts with different values" {
            $config1 = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Not -Be $config2.ConfiguredValue
        }

        It "copied successfully" {
            $results = Copy-DbaSpConfigure -Source $script:instance1 -Destination $script:instance2 -ConfigName RemoteQueryTimeout
            $results.Status | Should -Be "Successful"
        }

        It "retains the same properties" {
            $config1 = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should -Be $config2.ConfiguredValue
        }

        It "didn't modify the source" {
            $newconfig = (Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newconfig | Should -Be $sourceconfig
        }
    }
}
