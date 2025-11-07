#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRegServer",
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
                "Name",
                "ServerName",
                "Pattern",
                "ExcludeServerName",
                "Group",
                "ExcludeGroup",
                "Id",
                "IncludeSelf",
                "ResolveNetworkName",
                "IncludeLocal",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Registered server operations" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance $TestConfig.instance1
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

            <# Create the sub-group #>
            $srvName2 = "dbatoolsci-server2"
            $group2 = "dbatoolsci-group1a"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"

            $newGroup2 = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($groupStore, $group2)
            $newGroup2.Create()
            $dbStore.Refresh()

            $groupStore2 = $dbStore.ServerGroups[$group].ServerGroups[$group2]
            $newServer2 = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore2, $regSrvName2)
            $newServer2.ServerName = $srvName2
            $newServer2.Description = $regSrvDesc2
            $newServer2.Create()

            $regSrvName3 = "dbatoolsci-server3"
            $srvName3 = "dbatoolsci-server3"
            $regSrvDesc3 = "dbatoolsci-server3desc"
            $newServer3 = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($dbStore, $regSrvName3)
            $newServer3.ServerName = $srvName3
            $newServer3.Description = $regSrvDesc3
            $newServer3.Create()

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaRegServer -SqlInstance $TestConfig.instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -ErrorAction SilentlyContinue
            Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should return multiple objects" {
            $results = Get-DbaRegServer -SqlInstance $TestConfig.instance1 -Group $group
            $results.Count | Should -Be 2
            $results[0].ParentServer | Should -Not -BeNullOrEmpty
            $results[0].ComputerName | Should -Not -BeNullOrEmpty
            $results[0].InstanceName | Should -Not -BeNullOrEmpty
            $results[0].SqlInstance | Should -Not -BeNullOrEmpty
            $results[1].ParentServer | Should -Not -BeNullOrEmpty
            $results[1].ComputerName | Should -Not -BeNullOrEmpty
            $results[1].InstanceName | Should -Not -BeNullOrEmpty
            $results[1].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Should allow searching subgroups" {
            $results = Get-DbaRegServer -SqlInstance $TestConfig.instance1 -Group "$group\$group2"
            $results.Count | Should -Be 1
        }

        It "Should return the root server when excluding (see #3529)" {
            $results = Get-DbaRegServer -SqlInstance $TestConfig.instance1 -ExcludeGroup "$group\$group2"
            @($results | Where-Object Name -eq $srvName3).Count | Should -Be 1
        }

        It "Should filter subgroups" {
            $results = Get-DbaRegServer -SqlInstance $TestConfig.instance1 -Group $group -ExcludeGroup "$group\$group2"
            $results.Count | Should -Be 1
            $results.Group | Should -Be $group
        }

        It "Should filter by pattern using regex" {
            $results = Get-DbaRegServer -SqlInstance $TestConfig.instance1 -Pattern "^dbatoolsci-server[12]"
            $results.Count | Should -BeGreaterThan 0
            $results.Name | Should -Match "^dbatoolsci-server[12]"
        }

        It "Should filter by pattern matching ServerName property" {
            $results = Get-DbaRegServer -SqlInstance $TestConfig.instance1 -Pattern "server1$"
            $results.Count | Should -BeGreaterThan 0
            $results | Where-Object ServerName -match "server1$" | Should -Not -BeNullOrEmpty
        }

        # Property Comparisons will come later when we have the commands
    }
}