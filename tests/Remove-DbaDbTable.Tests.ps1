$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {

        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $instance2 -Name $dbname1

        $table1 = "dbatoolssci_table1_$(Get-Random)"
        $table2 = "dbatoolssci_table2_$(Get-Random)"
        $null = $instance2.Query("CREATE TABLE $table1 (Id int IDENTITY PRIMARY KEY, Value int DEFAULT 0);", $dbname1)
        $null = $instance2.Query("CREATE TABLE $table2 (Id int IDENTITY PRIMARY KEY, Value int DEFAULT 0);", $dbname1)
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $instance2 -Database $dbname1 -Confirm:$false
    }

    Context "commands work as expected" {

        It "removes a table" {
            (Get-DbaDbTable -SqlInstance $instance2 -Database $dbname1 -Table $table1) | Should -Not -BeNullOrEmpty
            Remove-DbaDbTable -SqlInstance $instance2 -Database $dbname1 -Table $table1 -Confirm:$false
            (Get-DbaDbTable -SqlInstance $instance2 -Database $dbname1 -Table $table1) | Should -BeNullOrEmpty
        }

        It "supports piping table" {
            (Get-DbaDbTable -SqlInstance $instance2 -Database $dbname1 -Table $table2) | Should -Not -BeNullOrEmpty
            Get-DbaDbTable -SqlInstance $instance2 -Database $dbname1 -Table $table2 | Remove-DbaDbTable -Confirm:$false
            (Get-DbaDbTable -SqlInstance $instance2 -Database $dbname1 -Table $table2) | Should -BeNullOrEmpty
        }
    }
}
