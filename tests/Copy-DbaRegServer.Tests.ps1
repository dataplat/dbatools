#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaRegServer",
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
                "Group",
                "SwitchServerName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $serverName = "dbatoolsci-server1"
        $groupName = "dbatoolsci-group1"
        $regServerName = "dbatoolsci-server12"
        $regServerDesc = "dbatoolsci-server123"

        # Create the objects.
        $sourceServer = Connect-DbaInstance $TestConfig.InstanceCopy2
        $regStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourceServer.ConnectionContext.SqlConnectionObject)
        $dbStore = $regStore.DatabaseEngineServerGroup

        $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $groupName)
        $newGroup.Create()
        $dbStore.Refresh()

        $groupStore = $dbStore.ServerGroups[$groupName]
        $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore, $regServerName)
        $newServer.ServerName = $serverName
        $newServer.Description = $regServerDesc
        $newServer.Create()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $newGroup.Drop()
        $destServer = Connect-DbaInstance $TestConfig.InstanceCopy1
        $destRegStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destServer.ConnectionContext.SqlConnectionObject)
        $destDbStore = $destRegStore.DatabaseEngineServerGroup
        $destGroupStore = $destDbStore.ServerGroups[$groupName]
        $destGroupStore.Drop()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying registered servers" {
        It "Should complete successfully" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                CMSGroup    = $groupName
            }
            $results = Copy-DbaRegServer @splatCopy
            $results.Status | Should -Be @("Successful", "Successful")
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Copy again with Force to get output for validation
            $splatCopyOutput = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                CMSGroup    = $groupName
                Force       = $true
            }
            $outputResult = @(Copy-DbaRegServer @splatCopyOutput)
        }

        It "Returns output of the expected type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the correct values for migration properties" {
            $outputResult[0].SourceServer | Should -Not -BeNullOrEmpty
            $outputResult[0].DestinationServer | Should -Not -BeNullOrEmpty
            $outputResult[0].Status | Should -BeIn @("Successful", "Skipped", "Failed")
        }
    }
}