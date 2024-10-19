param($ModuleName = 'dbatools')

Describe "Get-DbaRegServerGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegServerGroup
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Group",
                "ExcludeGroup",
                "Id",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance $global:instance1
            $regStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            $dbStore = $regStore.DatabaseEngineServerGroup

            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"

            $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $group)
            $newGroup.Create()
            $dbStore.Refresh()

            $groupStore = $dbStore.ServerGroups[$group]
            $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore, $regSrvName)
            $newServer.ServerName = $srvName
            $newServer.Description = $regSrvDesc
            $newServer.Create()

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
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $global:instance1 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $global:instance1 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "Should return one group" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group $group
            $results.Count | Should -Be 1
        }

        It "Should allow searching subgroups" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group "$group\$subGroup"
            $results.Count | Should -Be 1
        }

        It "Should return two groups" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group @($group, "$group\$subGroup")
            $results.Count | Should -Be 2
        }

        It "Verify the ExcludeGroup param is working" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group @($group, $group2) -ExcludeGroup $group
            $results.Count | Should -Be 1
            $results.Name | Should -Be $group2

            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -ExcludeGroup $group
            $results.Count | Should -Be 2
            ($results.Name -contains $group2 -and $results.Name -contains $group3) | Should -Be $true
        }
    }
}
