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
            $results = Get-DbaRegServerStore -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results.InstanceName | Should -Not -Be $null
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AnalysisServicesServerGroup",
                "AnalysisServicesServerGroupName",
                "AzureDataStudioConnectionStore",
                "CentralManagementServerGroup",
                "CentralManagementServerGroupName",
                "DatabaseEngineServerGroup",
                "DatabaseEngineServerGroupName",
                "DisplayName",
                "IntegrationServicesServerGroup",
                "IntegrationServicesServerGroupName",
                "IsLocal",
                "KeyChain",
                "ReportingServicesServerGroup",
                "ReportingServicesServerGroupName",
                "ServerGroups",
                "SqlServerCompactEditionServerGroup",
                "SqlServerCompactEditionServerGroupName"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.RegisteredServers\.RegisteredServersStore"
        }
    }
}