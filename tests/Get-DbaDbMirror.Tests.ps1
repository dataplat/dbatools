$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_mirroring"
        $db1 = "dbatoolsci_mirroring_db2"

        Remove-DbaDbMirror -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $null = $server.Query("CREATE DATABASE $db1")
        $null = $server.Query("CREATE DATABASE $db2")
    }
    AfterAll {
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $db1 -ErrorAction SilentlyContinue
    }

    It "returns more than one database" {
        $null = Invoke-DbaDbMirroring -Primary $script:instance2 -Mirror $script:instance3 -Database $db1 -Confirm:$false -Force -SharedPath C:\temp
        (Get-DbaDbMirror -SqlInstance $script:instance2).Count | Should -Be 2
    }


    It "returns just one database" {
        $null = Invoke-DbaDbMirroring -Primary $script:instance2 -Mirror $script:instance3 -Database $db1 -Confirm:$false -Force -SharedPath C:\temp
        (Get-DbaDbMirror -SqlInstance $script:instance2 -Database $db2).Count | Should -Be 1
    }
}