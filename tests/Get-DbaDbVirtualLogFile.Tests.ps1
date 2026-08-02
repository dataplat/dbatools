#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbVirtualLogFile",
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
                "IncludeSystemDBs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Get-DbaNoun
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testDbName = "dbatoolsci_getvlf"
        $splatDatabase = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Name            = $testDbName
            EnableException = $true
        }
        $null = New-DbaDatabase @splatDatabase

        # A database that cannot be opened. Taking one offline is the cheapest way to get
        # IsAccessible false, and the command cannot tell one inaccessible state from another.
        $offlineDb = "dbatoolsci_getvlf_offline_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineDb
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -Offline -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName

        # An offline database has to be brought back online before it can be dropped.
        $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -Online -Force -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $splatVirtualLogFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
            }
            $allResults = Get-DbaDbVirtualLogFile @splatVirtualLogFile
        }

        It "Should have correct properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "RecoveryUnitId",
                "FileId",
                "FileSize",
                "StartOffset",
                "FSeqNo",
                "Status",
                "Parity",
                "CreateLSN"
            )
            ($allResults[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProperties | Sort-Object)
        }

        It "Should have database name of $testDbName" {
            foreach ($result in $allResults) {
                $result.Database | Should -Be $testDbName
            }
        }
    }

    Context "Databases that cannot be opened" {
        It "Warns rather than returning nothing when the database is named" {
            $offlineResults = Get-DbaDbVirtualLogFile -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb
            $offlineResults | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -Match ([regex]::Escape($offlineDb))
        }

        It "Says the database was skipped because it is not accessible" {
            $null = Get-DbaDbVirtualLogFile -SqlInstance $TestConfig.InstanceSingle -Database $offlineDb
            ($WarnVar -join " ") | Should -Match "not accessible"
        }

        It "Stays quiet about a database that was excluded" {
            # The accessibility filter runs after -ExcludeDatabase, so a database the caller
            # excluded must not be reported as skipped.
            $excludedResults = Get-DbaDbVirtualLogFile -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $offlineDb
            $excludedResults | Should -Not -BeNullOrEmpty
            ($WarnVar -join " ") | Should -Not -Match ([regex]::Escape($offlineDb))
        }

        It "Still returns the accessible databases in a whole instance scan" {
            $scanResults = Get-DbaDbVirtualLogFile -SqlInstance $TestConfig.InstanceSingle
            $scanResults.Database | Should -Contain $testDbName
            $scanResults.Database | Should -Not -Contain $offlineDb
        }
    }
}