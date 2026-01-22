#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "DisableJobsOnDestination",
                "DisableJobsOnSource",
                "ExcludeServerProperties",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Copy-DbaAgentServer -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -ExcludeServerProperties -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has MigrationObject type name" {
            $result.PSObject.TypeNames | Should -Contain 'MigrationObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'DateTime',
                'SourceServer',
                'DestinationServer',
                'Name',
                'Type',
                'Status',
                'Notes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output with -ExcludeServerProperties" {
        BeforeAll {
            $result = Copy-DbaAgentServer -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -ExcludeServerProperties -EnableException
        }

        It "Sets Status to 'Skipped' when server properties are excluded" {
            $result.Status | Should -Be 'Skipped'
        }

        It "Has Type set to 'Agent Properties'" {
            $result.Type | Should -Be 'Agent Properties'
        }

        It "Has Name set to 'Server level properties'" {
            $result.Name | Should -Be 'Server level properties'
        }
    }
}