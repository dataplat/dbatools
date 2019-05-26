$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Group', 'NewGroup', 'InputObject', 'EnableException'
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

            $newGroup = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group
            $newServer = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

            $group2 = "dbatoolsci-group1a"
            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group2

            $group3 = "dbatoolsci-group1b"
            $newGroup3 = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group3
        }
        AfterAll {
            Get-DbaRegServer -SqlInstance $script:instance1 -Name $regSrvName  | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $script:instance1 -Group $group, $group2, $group3 | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "moves a piped group" {
            $results = $newGroup2, $newGroup3 | Move-DbaRegServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name, $newGroup.Name
        }

        It "moves a manually specified group" {
            $results = Move-DbaRegServerGroup -SqlInstance $script:instance1 -Group "$group\$group3" -NewGroup Default
            $results.Parent.Name | Should -Be 'DatabaseEngineServerGroup'
        }
    }
}