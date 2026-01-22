#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaOleDbProvider",
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
                "Provider",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        It "Returns OLE DB provider information" {
            $allResults = @(Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle)
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.OleDbProviderSettings]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Description',
                'AllowInProcess',
                'DisallowAdHocAccess',
                'DynamicParameters',
                'IndexAsAccessPath',
                'LevelZeroOnly',
                'NestedQueries',
                'NonTransactedUpdates'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}