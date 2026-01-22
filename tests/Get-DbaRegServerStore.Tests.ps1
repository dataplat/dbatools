#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRegServerStore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Components are properly retreived" {
        It "Should return the right values" {
            $results = Get-DbaRegServerStore -SqlInstance $TestConfig.InstanceSingle
            $results.InstanceName | Should -Not -Be $null
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaRegServerStore -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseEngineServerGroup',
                'ServerGroups',
                'RegisteredServers'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $addedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ParentServer'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $addedProps) {
                $actualProps | Should -Contain $prop -Because "dbatools adds '$prop' property via Add-Member"
            }
        }

        It "Excludes internal properties from default display" {
            $excludedProps = @(
                'ServerConnection',
                'DomainInstanceName',
                'DomainName',
                'Urn',
                'Properties',
                'Metadata',
                'Parent',
                'ConnectionContext',
                'PropertyMetadataChanged',
                'PropertyChanged'
            )
            # These properties should still exist (accessible via Select-Object *)
            # but are excluded from default display
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $excludedProps) {
                $actualProps | Should -Contain $prop -Because "excluded property '$prop' should still be accessible"
            }
        }
    }
}