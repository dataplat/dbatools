#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaRegServer" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaRegServer
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Group",
                "SwitchServerName",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaRegServer" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance $TestConfig.instance2
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
        $server = Connect-DbaInstance $TestConfig.instance1
        $regstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
        $dbstore = $regstore.DatabaseEngineServerGroup
        $groupstore = $dbstore.ServerGroups[$group]
        $groupstore.Drop()
    }

    Context "When copying registered servers" {
        BeforeAll {
            $results = Copy-DbaRegServer -Source $TestConfig.instance2 -Destination $TestConfig.instance1 -CMSGroup $group
        }

        It "Should complete successfully" {
            $results.Status | Should -Be @("Successful", "Successful")
        }
    }
}
