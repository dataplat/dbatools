$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $server = Connect-DbaInstance $script:instance1
            $regStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            $dbStore = $regStore.DatabaseEngineServerGroup
            
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            
            <# Create that first group #>
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
        }
        AfterAll {
            <# The top level group is all that is needed to be dropped #>
            $newGroup.Drop()
        }
        
        It "Should return one group" {
            $results = Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group $group
            $results.Count | Should Be 1
        }
        It "Should allow searching subgroups" {
            $results = Get-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group "$group\$group2"
            $results.Count | Should Be 1
        }
        
        # Property Comparisons will come later when we have the commands
    }
}