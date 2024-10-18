param($ModuleName = 'dbatools')

Describe "Copy-DbaRegServer" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaRegServer
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Group as a parameter" {
            $CommandUnderTest | Should -HaveParameter Group -Type System.String[]
        }
        It "Should have SwitchServerName as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SwitchServerName -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Integration Tests" {
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

        It "should copy registered servers successfully" {
            $results = Copy-DbaRegServer -Source $global:instance2 -Destination $global:instance1 -Group $group -WarningAction SilentlyContinue
            $results.Status | Should -Be @("Successful", "Successful")
        }
    }
}
