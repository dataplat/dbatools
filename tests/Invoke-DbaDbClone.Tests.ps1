#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbClone",
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
                "InputObject",
                "CloneDatabase",
                "ExcludeStatistics",
                "ExcludeQueryStore",
                "UpdateStatistics",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $dbname = "dbatoolsci_clonetest"
            $clonedb = "dbatoolsci_clonetest_CLONE"
            $clonedb2 = "dbatoolsci_clonetest_CLONE2"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $dbname")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "exists"
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "user database"
        }

        It "returns 1 result" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
            $results | Should -HaveCount 1
            $results.Name | Should -Be $clonedb
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "IsAccessible",
                "RecoveryModel",
                "LogReuseWaitStatus",
                "SizeMB",
                "Compatibility",
                "Collation",
                "Owner",
                "Encrypted",
                "LastFullBackup",
                "LastDiffBackup",
                "LastLogBackup"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
        }
    }
}