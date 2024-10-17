param($ModuleName = 'dbatools')

Describe "Import-DbaRegServer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaRegServer
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have Group parameter" {
            $CommandUnderTest | Should -HaveParameter Group -Type Object -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"

            $newGroup = Add-DbaRegServerGroup -SqlInstance $global:instance2 -Name $group
            $newServer = Add-DbaRegServer -SqlInstance $global:instance2 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

            $srvName2 = "dbatoolsci-server2"
            $group2 = "dbatoolsci-group1a"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"

            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $global:instance2 -Name $group2
            $newServer2 = Add-DbaRegServer -SqlInstance $global:instance2 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

            $regSrvName3 = "dbatoolsci-server3"
            $srvName3 = "dbatoolsci-server3"
            $regSrvDesc3 = "dbatoolsci-server3desc"

            $newServer3 = Add-DbaRegServer -SqlInstance $global:instance2 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
        }

        BeforeEach {
            Get-DbaRegServer -SqlInstance $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        AfterEach {
            Get-DbaRegServer -SqlInstance $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
            $results, $results2, $results3 | Remove-Item -ErrorAction Ignore
        }

        It "imports group objects" {
            $results = $newServer.Parent | Import-DbaRegServer -SqlInstance $global:instance2
            $results.Description | Should -Be $regSrvDesc
            $results.ServerName | Should -Be $srvName
            $results.Parent.Name | Should -Be $group
        }

        It "imports registered server objects" {
            $results2 = $newServer2 | Import-DbaRegServer -SqlInstance $global:instance2
            $results2.ServerName | Should -Be $newServer2.ServerName
            $results2.Parent.Name | Should -Be $newServer2.Parent.Name
        }

        It "imports a file from Export-DbaRegServer" {
            $results3 = $newServer3 | Export-DbaRegServer -Path C:\temp
            $results4 = Import-DbaRegServer -SqlInstance $global:instance2 -Path $results3
            $results4.ServerName | Should -Be @('dbatoolsci-server3')
            $results4.Description | Should -Be @('dbatoolsci-server3desc')
        }

        It "imports from a random object so long as it has ServerName" {
            $object = [pscustomobject]@{
                ServerName = 'dbatoolsci-randobject'
            }
            $results = $object | Import-DbaRegServer -SqlInstance $global:instance2
            $results.ServerName | Should -Be 'dbatoolsci-randobject'
            $results.Name | Should -Be 'dbatoolsci-randobject'
        }

        It "does not import object if ServerName does not exist" {
            $object = [pscustomobject]@{
                Name = 'dbatoolsci-randobject'
            }
            $results = $object | Import-DbaRegServer -SqlInstance $global:instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -BeNullOrEmpty
            $warn | Should -Match 'No servers added'
        }
    }
}
