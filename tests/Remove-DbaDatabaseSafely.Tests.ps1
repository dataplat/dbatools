#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDatabaseSafely",
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
                "Destination",
                "DestinationSqlCredential",
                "NoDbccCheckDb",
                "BackupFolder",
                "CategoryName",
                "JobOwner",
                "AllDatabases",
                "BackupCompression",
                "ReuseSourceFolderStructure",
                "Force",
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

        try {
            $db1 = "dbatoolsci_safely"
            $db2 = "dbatoolsci_safely_otherInstance"
            $server3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3
            $server3.Query("CREATE DATABASE $db1")
            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server2.Query("CREATE DATABASE $db1")
            $server2.Query("CREATE DATABASE $db2")
            $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        } catch { }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance3 -Database $db1 -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $TestConfig.instance2 -Job "Rationalised Database Restore Script for dbatoolsci_safely" -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $TestConfig.instance3 -Job "Rationalised Database Restore Script for dbatoolsci_safely_otherInstance" -ErrorAction SilentlyContinue
        Remove-Item -Path "$($TestConfig.Temp)\$db1*", "$($TestConfig.Temp)\$db2*" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {
        It "Should have database name of $db1" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.instance2 -Database $db1 -BackupFolder $TestConfig.Temp -NoDbccCheckDb
            foreach ($result in $results) {
                $result.DatabaseName | Should -Be $db1
            }
        }

        It -Skip:$($server1.EngineEdition -notmatch "Express") "should warn and quit on Express Edition" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.instance1 -Database $db1 -BackupFolder $TestConfig.Temp -NoDbccCheckDb -WarningAction SilentlyContinue -WarningVariable warn 3> $null
            $results | Should -Be $null
            $warn -match "Express Edition" | Should -Be $true
        }

        It "Should restore to another server" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.instance2 -Database $db2 -BackupFolder $TestConfig.Temp -NoDbccCheckDb -Destination $TestConfig.instance3
            foreach ($result in $results) {
                $result.SqlInstance | Should -Be $server2.SqlInstance
                $result.TestingInstance | Should -Be $server3.SqlInstance
            }
        }
    }
}