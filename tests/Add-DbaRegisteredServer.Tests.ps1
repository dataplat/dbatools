$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            $groupobject = Add-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Name $group
        }
        AfterAll {
            Remove-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName, $regSrvName -Confirm:$false
            Remove-DbaRegisteredServerGroup -SqlInstance $script:instance1 -Group $group -Confirm:$false
            $results1, $results2 | Remove-DbaRegisteredServer -Confirm:$false -WarningAction SilentlyContinue
            Remove-DbaRegisteredServer -SqlInstance $script:instance1 -Name $srvName, $regSrvName -Confirm:$false
        }

        It "adds a registered server" {
            $results1 = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $srvName
            $results1.Name | Should -Be $srvName
            $results1.ServerName | Should -Be $srvName
            $results1.SqlInstance | Should -Be $script:instance1
        }
        It "adds a registered server with extended properties" {
            $results2 = Add-DbaRegisteredServer -SqlInstance $script:instance1 -ServerName $RegsrvName -Name $srvName -Group $groupobject -Description $regSrvDesc
            $results2.ServerName | Should -Be $regSrvName
            $results2.Description | Should -Be $regSrvDesc
            $results2.Name | Should -Be $srvName
            $results2.SqlInstance | Should -Be $script:instance1
        }
    }
}