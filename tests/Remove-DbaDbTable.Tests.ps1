param($ModuleName = 'dbatools')

Describe "Remove-DbaDbTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbTable
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have Table as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Table[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Table[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
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
