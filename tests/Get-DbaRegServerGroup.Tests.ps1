#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRegServerGroup",
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
                "Group",
                "ExcludeGroup",
                "Id",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Registered Server Group operations" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance $TestConfig.InstanceSingle
            $regStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            $dbStore = $regStore.DatabaseEngineServerGroup

            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"

            <# Create that first group            #>
            $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $group)
            $newGroup.Create()
            $dbStore.Refresh()

            $groupStore = $dbStore.ServerGroups[$group]
            $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore, $regSrvName)
            $newServer.ServerName = $srvName
            $newServer.Description = $regSrvDesc
            $newServer.Create()

            <# Create the second group #>
            $srvName2 = "dbatoolsci-server1"
            $group2 = "dbatoolsci-group2"
            $regSrvName2 = "dbatoolsci-group2-server12"
            $regSrvDesc2 = "dbatoolsci-group2-server123"

            $newGroup2 = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $group2)
            $newGroup2.Create()
            $dbStore.Refresh()

            $groupStore2 = $dbStore.ServerGroups[$group2]
            $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore2, $regSrvName2)
            $newServer.ServerName = $srvName2
            $newServer.Description = $regSrvDesc2
            $newServer.Create()

            <# Create the third group #>
            $srvName3 = "dbatoolsci-server1"
            $group3 = "dbatoolsci-group3"
            $regSrvName3 = "dbatoolsci-group3-server12"
            $regSrvDesc3 = "dbatoolsci-group3-server123"

            $newGroup3 = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $group3)
            $newGroup3.Create()
            $dbStore.Refresh()

            $groupStore3 = $dbStore.ServerGroups[$group3]
            $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore3, $regSrvName3)
            $newServer.ServerName = $srvName3
            $newServer.Description = $regSrvDesc3
            $newServer.Create()

            <# Create the sub-group #>
            $subGroupSrvName = "dbatoolsci-subgroup-server"
            $subGroup = "dbatoolsci-group1a"
            $subGroupRegSrvName = "dbatoolsci-subgroup-server21"
            $subGroupRegSrvDesc = "dbatoolsci-subgroup-server321"

            $newSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($groupStore, $subGroup)
            $newSubGroup.Create()
            $dbStore.Refresh()

            $groupStoreSubGroup = $dbStore.ServerGroups[$group].ServerGroups[$subGroup]
            $subGroupServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStoreSubGroup, $subGroupRegSrvName)
            $subGroupServer.ServerName = $subGroupSrvName
            $subGroupServer.Description = $subGroupRegSrvDesc
            $subGroupServer.Create()

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -ErrorAction SilentlyContinue
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue
        }

        It "Should return one group" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $group
            $results.Count | Should -Be 1
        }

        It "Should allow searching subgroups" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group "$group\$subGroup"
            $results.Count | Should -Be 1
        }

        It "Should return two groups" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group @($group, "$group\$subGroup")
            $results.Count | Should -Be 2
        }

        It "Verify the ExcludeGroup param is working" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group @($group, $group2) -ExcludeGroup $group
            $results.Count | Should -Be 1
            $results.Name | Should -Be $group2

            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -ExcludeGroup $group
            $results.Count | Should -Be 2
            (($results.Name -contains $group2) -and ($results.Name -contains $group3)) | Should -Be $true
        }

        # Property Comparisons will come later when we have the commands
    }

    Context "The connection of the caller is left alone (#10572)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only a non-pooled connection can show this. SMO silently reopens a pooled connection, so the test
            # would pass even with the disconnect this is about.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $callerResult = Get-DbaRegServerGroup -SqlInstance $callerServer -Id 1

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still returns the group" {
            $callerResult.Name | Should -Be "DatabaseEngineServerGroup"
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }
}