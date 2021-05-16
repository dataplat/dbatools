$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'View', 'InputObject', 'EnableException'
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
        It 'Removes user views' {
            $null = $server.Query("CREATE VIEW $view1 (a) AS (SELECT @@VERSION );" , $dbname1)
            $null = $server.Query("CREATE VIEW $view2 (b) AS (SELECT * from $view1);", $dbname1)
            $result0 = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView
            Remove-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -Confirm:$false
            $result1 = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -ExcludeSystemView

            $result0.Count | Should BeGreaterThan $result1.Count
            $result1.Name -contains $view1  | Should Be $false
            $result1.Name -contains $view2  | Should Be $false
        }

        It 'Accepts a list of views' {
            $null = $server.Query("CREATE VIEW $view1 (a) AS (SELECT @@VERSION );" , $dbname1)
            $null = $server.Query("CREATE VIEW $view2 (b) AS (SELECT * from $view1);", $dbname1)
            $result0 = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1
            Remove-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -View $view1 -Confirm:$false
            $result1 = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1

            $result0.Count | Should BeGreaterThan $result1.Count
            $result1.Name -contains $view1  | Should Be $false
            $result1.Name -contains $view2  | Should Be $true
        }

        It 'Accepts input from Get-DbaDbView' {
            $result0 = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1 -View $view2
            $result0 | Remove-DbaDbView -Confirm:$false
            $result1 = Get-DbaDbView -SqlInstance $script:instance2 -Database $dbname1

            $result1.Name -contains $view2  | Should Be $false
        }

    }
}