$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ServerName', 'Group', 'ExcludeGroup', 'Id', 'IncludeSelf', 'ResolveNetworkName', 'IncludeLocal', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $server = Connect-DbaInstance $script:instance1
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
        }
        AfterAll {
            Get-DbaRegServer -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "Should return multiple objects" {
            $results = Get-DbaRegServer -SqlInstance $script:instance1 -Group $group
            $results.Count | Should Be 2
        }
        It "Should allow searching subgroups" {
            $results = Get-DbaRegServer -SqlInstance $script:instance1 -Group "$group\$group2"
            $results.Count | Should Be 1
        }
        It "Should return the root server when excluding (see #3529)" {
            $results = Get-DbaRegServer -SqlInstance $script:instance1 -ExcludeGroup "$group\$group2"
            @($results | Where-Object Name -eq $srvName3).Count | Should -Be 1
        }
        It "Should filter subgroups" {
            $results = Get-DbaRegServer -SqlInstance $script:instance1 -Group $group -ExcludeGroup "$group\$group2"
            $results.Count | Should Be 1
            $results.Group | Should Be $group
        }

        # Property Comparisons will come later when we have the commands
    }
}