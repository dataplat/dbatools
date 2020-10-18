$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
        $server.Query("DBCC CHECKDB")
        $dbname = "dbatoolsci_]_$(Get-Random)"
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname -Owner sa
        $db.Query("DBCC CHECKDB")
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -confirm:$false
    }
    Context "Command actually works" {
        $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1 -Database master
        It "LastGoodCheckDb is a valid date" {
            $results.LastGoodCheckDb -ne $null | Should Be $true
            $results.LastGoodCheckDb -is [datetime] | Should Be $true
        }

        $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1 -WarningAction SilentlyContinue
        It "returns more than 3 results" {
            ($results).Count -gt 3 | Should Be $true
        }

        $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1 -Database $dbname
        It "LastGoodCheckDb is a valid date for database with embedded ] characters" {
            $results.LastGoodCheckDb -ne $null | Should Be $true
            $results.LastGoodCheckDb -is [datetime] | Should Be $true
        }
    }

    Context "Piping works" {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $results = $server | Get-DbaLastGoodCheckDb -Database $dbname, master
        It "LastGoodCheckDb accepts piped input from Connect-DbaInstance" {
            ($results).Count -eq 2 | Should Be $true
        }

        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname, master
        $results = $db | Get-DbaLastGoodCheckDb
        It "LastGoodCheckDb accepts piped input from Get-DbaDatabase" {
            ($results).Count -eq 2 | Should Be $true
        }
    }

    Context "Doesn't return duplicate results" {
        $results = Get-DbaLastGoodCheckDb -SqlInstance $script:instance1, $script:instance2 -Database $dbname
        It "LastGoodCheckDb doesn't return duplicates when multiple servers are passed in" {
            ($results | Group-Object SqlInstance, Database | Where-Object Count -gt 1) | Should BeNullOrEmpty
        }
    }
}