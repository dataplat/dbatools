$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $db1 = "dbatoolsci_mirroring"
        $db2 = "dbatoolsci_mirroring_db2"

        Remove-DbaDbMirror -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false

        $null = $server.Query("CREATE DATABASE $db1")
        $null = $server.Query("CREATE DATABASE $db2")
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 | Remove-DbaDbMirror -Confirm:$false
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }

    It -Skip "returns more than one database" {
        $null = Invoke-DbaDbMirroring -Primary $TestConfig.instance2 -Mirror $TestConfig.instance3 -Database $db1, $db2 -Confirm:$false -Force -SharedPath C:\temp -WarningAction Continue
        (Get-DbaDbMirror -SqlInstance $TestConfig.instance3).Count | Should -Be 2
    }


    It -Skip "returns just one database" {
        (Get-DbaDbMirror -SqlInstance $TestConfig.instance3 -Database $db2).Count | Should -Be 1
    }

    It -Skip "returns 2x1 database" {
        (Get-DbaDbMirror -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db2).Count | Should -Be 2
    }
}
