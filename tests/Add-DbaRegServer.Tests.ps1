param($ModuleName = 'dbatools')

Describe "Add-DbaRegServer" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaRegServer
        }
        $paramList = @(
            'SqlInstance',
            'SqlCredential',
            'ServerName',
            'Name',
            'Description',
            'Group',
            'ActiveDirectoryTenant',
            'ActiveDirectoryUserId',
            'ConnectionString',
            'OtherParams',
            'InputObject',
            'ServerObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
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
            $results2 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $RegsrvName -Name $srvName -Group $groupobject -Description $regSrvDesc
            $results2.ServerName | Should -Be $regSrvName
            $results2.Description | Should -Be $regSrvDesc
            $results2.Name | Should -Be $srvName
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
