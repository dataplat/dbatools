param($ModuleName = 'dbatools')

Describe "Remove-DbaDbTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbTable
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
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
