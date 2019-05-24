$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'InputObject', 'Group', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"

            $newGroup = Add-DbaRegServerGroup -SqlInstance $script:instance2 -Name $group
            $newServer = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

            $srvName2 = "dbatoolsci-server2"
            $group2 = "dbatoolsci-group1a"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"

            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $script:instance2 -Name $group2
            $newServer2 = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

            $regSrvName3 = "dbatoolsci-server3"
            $srvName3 = "dbatoolsci-server3"
            $regSrvDesc3 = "dbatoolsci-server3desc"

            $newServer3 = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
        }
        BeforeEach {
            Get-DbaRegServer -SqlInstance $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $script:instance2| Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }
        Aftereach {
            Get-DbaRegServer -SqlInstance $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $script:instance2| Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
            $results, $results2, $results3 | Remove-Item -ErrorAction Ignore
        }

        It "imports group objects" {
            $results = $newServer.Parent | Import-DbaRegServer -SqlInstance $script:instance2
            $results.Description | Should -Be $regSrvDesc
            $results.ServerName | Should -Be $srvName
            $results.Parent.Name | Should -Be $group
        }

        It "imports registered server objects" {
            $results2 = $newServer2 | Import-DbaRegServer -SqlInstance $script:instance2
            $results2.ServerName | Should -Be $newServer2.ServerName
            $results2.Parent.Name | Should -Be $newServer2.Parent.Name
        }

        It "imports a file from Export-DbaRegServer" {
            $results3 = $newServer3 | Export-DbaRegServer -Path C:\temp
            $results4 = Import-DbaRegServer -SqlInstance $script:instance2 -Path $results3
            $results4.ServerName | Should -Be @('dbatoolsci-server3')
            $results4.Description | Should -Be @('dbatoolsci-server3desc')
        }
        It "imports from a random object so long as it has ServerName" {
            $object = [pscustomobject]@{
                ServerName = 'dbatoolsci-randobject'
            }
            $results = $object | Import-DbaRegServer -SqlInstance $script:instance2
            $results.ServerName | Should -Be 'dbatoolsci-randobject'
            $results.Name | Should -Be 'dbatoolsci-randobject'
        }
        It "does not import object if ServerName does not exist" {
            $object = [pscustomobject]@{
                Name = 'dbatoolsci-randobject'
            }
            $results = $object | Import-DbaRegServer -SqlInstance $script:instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -Be $null
            $warn | Should -Match 'No servers added'
        }
    }
}