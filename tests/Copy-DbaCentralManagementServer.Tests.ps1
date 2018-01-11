$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $server = Connect-DbaInstance $script:instance2
            $regstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            $dbstore = $regstore.DatabaseEngineServerGroup

            $servername = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regservername = "dbatoolsci-server12"
            $regserverdescription = "dbatoolsci-server123"

            $newgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbstore, $group)
            $newgroup.Create()
            $dbstore.Refresh()

            $groupstore = $dbstore.ServerGroups[$group]
            $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupstore, $regservername)
            $newserver.ServerName = $servername
            $newserver.Description = $regserverdescription
            $newserver.Create()
        }
        AfterAll {
            $newgroup.Drop()
            $server = Connect-DbaInstance $script:instance1
            $regstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            $dbstore = $regstore.DatabaseEngineServerGroup
            $groupstore = $dbstore.ServerGroups[$group]
            $groupstore.Drop()
        }

        $results = Copy-DbaCentralManagementServer -Source $script:instance2 -Destination $script:instance1 -WarningVariable warn -WarningAction SilentlyContinue -CMSGroup $group

        It "should report success" {
            $results.Status | Should Be "Successful", "Successful"
        }

        # Property Comparisons will come later when we have the commands
    }
}
