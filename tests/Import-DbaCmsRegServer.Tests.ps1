$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'InputObject', 'Group', 'EnableException'
        $SupportShouldProcess = $false
        $paramCount = $knownParameters.Count
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }

        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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

            $newGroup = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group
            $newServer = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

            $srvName2 = "dbatoolsci-server2"
            $group2 = "dbatoolsci-group1a"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"

            $newGroup2 = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group2
            $newServer2 = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

            $regSrvName3 = "dbatoolsci-server3"
            $srvName3 = "dbatoolsci-server3"
            $regSrvDesc3 = "dbatoolsci-server3desc"

            $newServer3 = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
        }
        AfterAll {
            Get-DbaCmsRegServer -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServer -Confirm:$false
            Get-DbaCmsRegServerGroup -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServerGroup -Confirm:$false
        }

        It "imports group objects" {
            $results = $newServer.Parent | Import-DbaCmsRegServer -SqlInstance $script:instance2
            $results.Description | Should -Be $regSrvDesc
            $results.ServerName | Should -Be $srvName
            $results.Parent.Name | Should -Be $group
        }

        It "imports registered server objects" {
            $results2 = $newServer2 | Import-DbaCmsRegServer -SqlInstance $script:instance2
            $results2.ServerName | Should -Be $newServer2.ServerName
            $results2.Parent.Name | Should -Be $newServer2.Parent.Name
        }

        It "imports a file from Export-DbaCmsRegServer" {
            $results3 = $newServer3 | Export-DbaCmsRegServer -Path C:\temp\dbatoolsci_regserverexport.xml
            $results4 = Import-DbaCmsRegServer -SqlInstance $script:instance2 -Path $results3
            $results4.ServerName | Should -Be @('dbatoolsci-server3', 'dbatoolsci-server1')
            $results4.Description | Should -Be @('dbatoolsci-server3desc', 'dbatoolsci-server123')
        }
        It "imports from a random object so long as it has ServerName" {
            $object = [pscustomobject]@{
                ServerName = 'dbatoolsci-randobject'
            }
            $results = $object | Import-DbaCmsRegServer -SqlInstance $script:instance2
            $results.ServerName | Should -Be 'dbatoolsci-randobject'
            $results.Name | Should -Be 'dbatoolsci-randobject'
        }
        It "does not import object if ServerName does not exist" {
            $object = [pscustomobject]@{
                Name = 'dbatoolsci-randobject'
            }
            $results = $object | Import-DbaCmsRegServer -SqlInstance $script:instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -Be $null
            $warn | Should -Match 'No servers added'
        }
    }
}