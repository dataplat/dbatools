$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}


Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_mirroring"
        $db2 = "dbatoolsci_mirroring_db2"

        Remove-DbaDbMirror -SqlInstance $script:instance2, $script:instance3 -Database $db1, $db2 -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false

        $null = $server.Query("CREATE DATABASE $db1")
        $null = $server.Query("CREATE DATABASE $db2")
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Database $db1, $db2 | Remove-DbaDbMirror -Confirm:$false
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }

    It -Skip "returns more than one database" {
        $null = Invoke-DbaDbMirroring -Primary $script:instance2 -Mirror $script:instance3 -Database $db1, $db2 -Confirm:$false -Force -SharedPath C:\temp -WarningAction Continue
        (Get-DbaDbMirror -SqlInstance $script:instance3).Count | Should -Be 2
    }


    It -Skip "returns just one database" {
        (Get-DbaDbMirror -SqlInstance $script:instance3 -Database $db2).Count | Should -Be 1
    }

    It -Skip "returns 2x1 database" {
        (Get-DbaDbMirror -SqlInstance $script:instance2, $script:instance3 -Database $db2).Count | Should -Be 2
    }
}