$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Group', 'SwitchServerName', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

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

        $results = Copy-DbaRegServer -Source $script:instance2 -Destination $script:instance1 -WarningVariable warn -WarningAction SilentlyContinue -CMSGroup $group

        It "should report success" {
            $results.Status | Should Be "Successful", "Successful"
        }

        # Property Comparisons will come later when we have the commands
    }
}