#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLastGoodCheckDb",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatConnection = @{
            SqlInstance = $TestConfig.InstanceMulti1
            Database    = "master"
        }
        $server = Connect-DbaInstance @splatConnection
        $server.Query("DBCC CHECKDB")
        $dbname = "dbatoolsci_]_$(Get-Random)"

        $splatDatabase = @{
            SqlInstance = $TestConfig.InstanceMulti1
            Name        = $dbname
            Owner       = "sa"
        }
        $db = New-DbaDatabase @splatDatabase
        $db.Query("DBCC CHECKDB")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $masterResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1 -Database master
            $allResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1 -WarningAction SilentlyContinue
            $dbResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname
        }

        It "LastGoodCheckDb is a valid date" {
            $masterResults.LastGoodCheckDb -ne $null | Should -Be $true
            $masterResults.LastGoodCheckDb -is [datetime] | Should -Be $true
        }

        It "returns more than 3 results" {
            $allResults.Count -gt 3 | Should -Be $true
        }

        It "LastGoodCheckDb is a valid date for database with embedded ] characters" {
            $dbResults.LastGoodCheckDb -ne $null | Should -Be $true
            $dbResults.LastGoodCheckDb -is [datetime] | Should -Be $true
        }
    }

    Context "Piping works" {
        BeforeAll {
            $serverConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $serverPipeResults = $serverConnection | Get-DbaLastGoodCheckDb -Database $dbname, master

            $databases = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname, master
            $databasePipeResults = $databases | Get-DbaLastGoodCheckDb
        }

        It "LastGoodCheckDb accepts piped input from Connect-DbaInstance" {
            $serverPipeResults.Count -eq 2 | Should -Be $true
        }

        It "LastGoodCheckDb accepts piped input from Get-DbaDatabase" {
            $databasePipeResults.Count -eq 2 | Should -Be $true
        }
    }

    Context "Carries CreateVersion and DbccFlags across piped records" {
        # CreateVersion and DbccFlags are only assigned on the DBCC DBINFO branch, which needs
        # SQL 2008 or older or a sysadmin connection. They are read unconditionally by the output,
        # so on SQL 2008 R2 and newer a non-sysadmin record re-emits whatever the previous record
        # left behind. These two records pin that behaviour: record one connects as a sysadmin and
        # assigns, record two connects as a plain login and must repeat record one's values.
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $limitedLogin = "dbatoolsci_limited_$(Get-Random)"
            $limitedPassword = ConvertTo-SecureString -String "dbatools.IO_$(Get-Random)" -AsPlainText -Force

            $splatLimitedLogin = @{
                SqlInstance    = $TestConfig.InstanceMulti1
                Login          = $limitedLogin
                SecurePassword = $limitedPassword
                Force          = $true
            }
            $null = New-DbaLogin @splatLimitedLogin

            $limitedCredential = New-Object System.Management.Automation.PSCredential ($limitedLogin, $limitedPassword)

            $sysadminDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database master
            $limitedDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $limitedCredential -Database master

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $carryResults = @($sysadminDatabase, $limitedDatabase | Get-DbaLastGoodCheckDb)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $limitedLogin -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "assigns CreateVersion and DbccFlags on the sysadmin record" {
            $carryResults.Count | Should -Be 2
            $carryResults[0].CreateVersion | Should -Not -BeNullOrEmpty
        }

        It "re-emits the sysadmin record's CreateVersion and DbccFlags on the non-sysadmin record" {
            $carryResults[1].DataPurityEnabled | Should -BeNullOrEmpty
            $carryResults[1].CreateVersion | Should -Be $carryResults[0].CreateVersion
            $carryResults[1].DbccFlags | Should -Be $carryResults[0].DbccFlags
        }
    }

    Context "Doesn't return duplicate results" {
        BeforeAll {
            $duplicateResults = Get-DbaLastGoodCheckDb -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $dbname
        }

        It "LastGoodCheckDb doesn't return duplicates when multiple servers are passed in" {
            ($duplicateResults | Group-Object SqlInstance, Database | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        }
    }
}