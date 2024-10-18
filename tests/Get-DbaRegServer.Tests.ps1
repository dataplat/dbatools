param($ModuleName = 'dbatools')

Describe "Get-DbaRegServer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance $global:instance1
        $regStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext.SqlConnectionObject)
        $dbStore = $regStore.DatabaseEngineServerGroup

        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        # Create that first group
        $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $group)
        $newGroup.Create()
        $dbStore.Refresh()

        $groupStore = $dbStore.ServerGroups[$group]
        $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore, $regSrvName)
        $newServer.ServerName = $srvName
        $newServer.Description = $regSrvDesc
        $newServer.Create()

        # Create the sub-group
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
        Get-DbaRegServer -SqlInstance $global:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $global:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegServer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String[]
        }
        It "Should have ServerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerName -Type System.String[]
        }
        It "Should have Group as a parameter" {
            $CommandUnderTest | Should -HaveParameter Group -Type System.String[]
        }
        It "Should have ExcludeGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeGroup -Type System.String[]
        }
        It "Should have Id as a parameter" {
            $CommandUnderTest | Should -HaveParameter Id -Type System.Int32[]
        }
        It "Should have IncludeSelf as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSelf -Type System.Management.Automation.SwitchParameter
        }
        It "Should have ResolveNetworkName as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ResolveNetworkName -Type System.Management.Automation.SwitchParameter
        }
        It "Should have IncludeLocal as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeLocal -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        It "Should return multiple objects" {
            $results = Get-DbaRegServer -SqlInstance $global:instance1 -Group $group
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
            $results = Get-DbaRegServer -SqlInstance $global:instance1 -Group "$group\$group2"
            $results.Count | Should -Be 1
        }

        It "Should return the root server when excluding (see #3529)" {
            $results = Get-DbaRegServer -SqlInstance $global:instance1 -ExcludeGroup "$group\$group2"
            @($results | Where-Object Name -eq $srvName3).Count | Should -Be 1
        }

        It "Should filter subgroups" {
            $results = Get-DbaRegServer -SqlInstance $global:instance1 -Group $group -ExcludeGroup "$group\$group2"
            $results.Count | Should -Be 1
            $results.Group | Should -Be $group
        }
    }
}
