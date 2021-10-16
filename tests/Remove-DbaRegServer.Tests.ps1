$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ServerName', 'Group', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            $newServer = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

            $srvName2 = "dbatoolsci-server2"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"
            $newServer2 = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2
        }
        AfterAll {
            Get-DbaRegServer -SqlInstance $script:instance1 -Name $regSrvName, $regSrvName2, $regSrvName3 | Remove-DbaRegServer -Confirm:$false
        }

        It "supports dropping via the pipeline" {
            $results = $newServer | Remove-DbaRegServer -Confirm:$false
            $results.Name | Should -Be $regSrvName
            $results.Status | Should -Be 'Dropped'
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServer -Confirm:$false -SqlInstance $script:instance1 -Name $regSrvName2
            $results.Name | Should -Be $regSrvName2
            $results.Status | Should -Be 'Dropped'
        }
    }
}