$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'View', 'Schema', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {

        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName

        $view1 = "dbatoolssci_view1_$(Get-Random)"
        $schema1 = "dbatoolssci_schema1_$(Get-Random)"
        $null = $instance2.Query("CREATE VIEW $schema1.$view1 (a) AS (SELECT @@VERSION );" , $dbname1)
        $null = $instance2.Query("CREATE VIEW $view2 (b) AS (SELECT * from $view1);", $dbname1)
    }

    AfterAll {
        $null = $dbname1 | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        #It "removes a view" {
        #    (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view1 -Schema $schema1) | Should -Not -BeNullOrEmpty
        #    Remove-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view1 -Schema $schema1 -Confirm:$false
        #    (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view1 -Schema $schema1) | Should -BeNullOrEmpty
        #}

        It "supports piping view" {
            (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view2 -Schema $schema1) | Should -Not -BeNullOrEmpty
            Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view2 -Schema $schema1 | Remove-DbaDbView -Confirm:$false
            (Get-DbaDbView -SqlInstance $instance2 -Database $dbname1 -View $view2 -Schema $schema1) | Should -BeNullOrEmpty
        }
    }
}