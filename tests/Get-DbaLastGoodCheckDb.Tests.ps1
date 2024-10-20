param($ModuleName = 'dbatools')

Describe "Get-DbaLastGoodCheckDb" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLastGoodCheckDb
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1 -Database master
            $server.Query("DBCC CHECKDB")
            $dbname = "dbatoolsci_]_$(Get-Random)"
            $db = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname -Owner sa
            $db.Query("DBCC CHECKDB")
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        }

        It "LastGoodCheckDb is a valid date" {
            $results = Get-DbaLastGoodCheckDb -SqlInstance $global:instance1 -Database master
            $results.LastGoodCheckDb | Should -Not -BeNullOrEmpty
            $results.LastGoodCheckDb | Should -BeOfType [datetime]
        }

        It "returns more than 3 results" {
            $results = Get-DbaLastGoodCheckDb -SqlInstance $global:instance1 -WarningAction SilentlyContinue
            $results.Count | Should -BeGreaterThan 3
        }

        It "LastGoodCheckDb is a valid date for database with embedded ] characters" {
            $results = Get-DbaLastGoodCheckDb -SqlInstance $global:instance1 -Database $dbname
            $results.LastGoodCheckDb | Should -Not -BeNullOrEmpty
            $results.LastGoodCheckDb | Should -BeOfType [datetime]
        }
    }

    Context "Piping works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $dbname = "dbatoolsci_]_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname -Owner sa
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        }

        It "LastGoodCheckDb accepts piped input from Connect-DbaInstance" {
            $results = $server | Get-DbaLastGoodCheckDb -Database $dbname, master
            $results.Count | Should -Be 2
        }

        It "LastGoodCheckDb accepts piped input from Get-DbaDatabase" {
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname, master
            $results = $db | Get-DbaLastGoodCheckDb
            $results.Count | Should -Be 2
        }
    }

    Context "Doesn't return duplicate results" {
        It "LastGoodCheckDb doesn't return duplicates when multiple servers are passed in" {
            $dbname = "dbatoolsci_]_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname -Owner sa
            $results = Get-DbaLastGoodCheckDb -SqlInstance $global:instance1, $global:instance2 -Database $dbname
            ($results | Group-Object SqlInstance, Database | Where-Object Count -gt 1) | Should -BeNullOrEmpty
            $null = Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        }
    }
}
