<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemSp', 'Name', 'Schema', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $random = Get-Random
        $db1Name = "dbatoolsci_$random"
        $db1 = New-DbaDatabase -SqlInstance $server -Name $db1Name
        $procName = "proc1"
        $db1.Query("CREATE PROCEDURE $procName AS SELECT 1")

        $schemaName = "schema1"
        $procName2 = "proc2"
        $db1.Query("CREATE SCHEMA $schemaName")
        $db1.Query("CREATE PROCEDURE $schemaName.$procName2 AS SELECT 1")
    }
    AfterAll {
        $db1 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command actually works" {
        $results = Get-DbaDbStoredProcedure -SqlInstance $TestConfig.instance2 -Database $db1Name
        It "Should have standard properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance'.Split(',')
            ($results[0].PsObject.Properties.Name | Where-Object { $_ -in $ExpectedProps } | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Should get test procedure: $procName" {
            ($results | Where-Object Name -eq $procName).Name | Should -Be $true
        }
        It "Should include system procedures" {
            ($results | Where-Object Name -eq 'sp_columns') | Should -Be $true
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no procs from master database" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $TestConfig.instance2 -ExcludeDatabase master
            $results.Database | Should -Not -Contain 'master'
        }
        It "Should exclude system procedures" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $TestConfig.instance2 -Database $db1Name -ExcludeSystemSp
            $results | Where-Object Name -eq 'sp_helpdb' | Should -BeNullOrEmpty
        }
    }

    Context "Piping works" {
        It "Should allow piping from string" {
            $results = $TestConfig.instance2 | Get-DbaDbStoredProcedure -Database $db1Name
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }
        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db1Name | Get-DbaDbStoredProcedure
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Search by name and schema" {
        It "Search by name" {
            $results = $TestConfig.instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Name $procName
            $results.Name | Should -Be $procName
            $results.DatabaseId | Should -Be $db1.Id
        }
        It "Search by 2 part name" {
            $results = $TestConfig.instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Name "$schemaName.$procName2"
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }
        It "Search by 3 part name and omit the -Database param" {
            $results = $TestConfig.instance2 | Get-DbaDbStoredProcedure -Name "$db1Name.$schemaName.$procName2"
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
            $results.Database | Should -Be $db1Name
        }
        It "Search by name and schema params" {
            $results = $TestConfig.instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Name $procName2 -Schema $schemaName
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }
        It "Search by schema name" {
            $results = $TestConfig.instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Schema $schemaName
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }
    }
}
