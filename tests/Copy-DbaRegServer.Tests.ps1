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

    Context "Output Validation" {
        BeforeAll {
            $splatCopy = @{
                Source          = $TestConfig.InstanceCopy2
                Destination     = $TestConfig.InstanceCopy1
                CMSGroup        = $groupName
                EnableException = $true
            }
            $result = Copy-DbaRegServer @splatCopy
        }

        It "Returns PSCustomObject with MigrationObject type" {
            $result[0].PSObject.TypeNames | Should -Contain "MigrationObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns multiple objects for different migration actions" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Status property contains valid values" {
            $validStatuses = @("Successful", "Skipped", "Failed")
            foreach ($item in $result) {
                $validStatuses | Should -Contain $item.Status
            }
        }

        It "Type property contains valid object types" {
            $validTypes = @("CMS Destination Group", "CMS Group", "CMS Instance")
            foreach ($item in $result) {
                $validTypes | Should -Contain $item.Type
            }
        }
    }
}