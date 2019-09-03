$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('WhatIf', 'Confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db110 = "dbatoolsci11_$(Get-Random)"
        $db140 = "dbatoolsci13_$(Get-Random)"

        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $server.Query("CREATE DATABASE $db110")
        $server.Query("CREATE DATABASE $db140")
        $server.Query("ALTER DATABASE $db110 SET COMPATIBILITY_LEVEL = 110;")
    }
    AfterAll {
        try {
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $server.Query("DROP DATABASE $db110")
        $server.Query("DROP DATABASE $db140")
        } catch {
            # Don't care.
        }
    }
    Context "Gets compatibility for multiple databases" {
        $results = Get-DbaDbCompatibility -SqlInstance $script:instance3
        It "Gets results" {
            $results | Should -Not -Be $null
        }
        $result110 = $results | Where-Object Database -eq $db110

        It "Should return Compatibility of Version110 for $db110" {
            $result110.Compatibility | Should -Be "Version110"
        }
        It "Should return Level of 11 for $db110" {
            $result110.Level | Should -Be 11
        }

        $result140 = $results | Where-Object Database -eq $db140

        It "Should return Compatibility of Version140 for $db140" {
            $result140.Compatibility | Should -Be "Version140"
        }
        It "Should return Level of 14 for $db140" {
            $result140.Level | Should -Be 14
        }
    }
    Context "Gets compatibility for one database" {
        $results = Get-DbaDbCompatibility -SqlInstance $script:instance3 -database $db140

        It "Gets results" {
            $results | Should -Not -Be $null
        }
    }
}