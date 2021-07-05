$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $view1 = "dbatoolssci_view1_$(Get-Random)"
        $view2 = "dbatoolssci_view2_$(Get-Random)"
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1 -confirm:$false
    }

    Context "Functionality" {
        It 'Accepts input from Get-DbaDbView' {
            $null = $server.Query("CREATE VIEW $view1 (a) AS (SELECT @@VERSION );" , $dbname1)
            $null = $server.Query("CREATE VIEW $view2 (b) AS (SELECT * from $view1);", $dbname1)
            $result0 = Get-DbaDbView -SqlInstance $server -Database $dbname1 -View $view1, $view2
            $result1 = Get-DbaDbView -SqlInstance $server -Database $dbname1 -View $view2
            $result1 | Remove-DbaDbView -Confirm:$false
            $result2 = Get-DbaDbView -SqlInstance $server -Database $dbname1 -View $view1, $view2

            $result0.Count | Should Be 2
            $result1.Count | Should Be 1
            $result2.Count | Should Be 1
            $result2.Name -contains $view2  | Should Be $false
        }

    }
}