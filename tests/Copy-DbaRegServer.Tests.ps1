param($ModuleName = 'dbatools')

Describe "Copy-DbaRegServer" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaRegServer
        }
        $parms = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'Group',
            'SwitchServerName',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance $global:instance2
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
            $server = Connect-DbaInstance $global:instance1
            $regstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
            $dbstore = $regstore.DatabaseEngineServerGroup
            $groupstore = $dbstore.ServerGroups[$group]
            $groupstore.Drop()
        }

        It "should report success" {
            $results = Copy-DbaRegServer -Source $global:instance2 -Destination $global:instance1 -WarningAction SilentlyContinue -CMSGroup $group
            $results.Status | Should -Be @("Successful", "Successful")
        }

        # Property Comparisons will come later when we have the commands
    }
}
