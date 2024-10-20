param($ModuleName = 'dbatools')

Describe "Add-DbaRegServer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaRegServer
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "ServerName",
            "Name",
            "Description",
            "Group",
            "ActiveDirectoryTenant",
            "ActiveDirectoryUserId",
            "ConnectionString",
            "OtherParams",
            "InputObject",
            "ServerObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            $groupobject = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $global:instance1, $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $global:instance1, $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "adds a registered server" {
            $results1 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $srvName
            $results1.Name | Should -Be $srvName
            $results1.ServerName | Should -Be $srvName
            $results1.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "adds a registered server with extended properties" {
            $results2 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $regSrvName -Name $srvName -Group $groupobject -Description $regSrvDesc
            $results2.ServerName | Should -Be $regSrvName
            $results2.Description | Should -Be $regSrvDesc
            $results2.Name | Should -Be $srvName
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
