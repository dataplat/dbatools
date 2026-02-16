#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbStoredProcedure",
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
                "ExcludeSystemSp",
                "Name",
                "Schema",
                "InputObject",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $db1Name = "dbatoolsci_$random"
        $db1 = New-DbaDatabase -SqlInstance $server -Name $db1Name
        $procName = "proc1"
        $db1.Query("CREATE PROCEDURE $procName AS SELECT 1")

        $schemaName = "schema1"
        $procName2 = "proc2"
        $db1.Query("CREATE SCHEMA $schemaName")
        $db1.Query("CREATE PROCEDURE $schemaName.$procName2 AS SELECT 1")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db1 | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -OutVariable "global:dbatoolsciOutput"
        }

        It "Should have standard properties" {
            $ExpectedProps = @("ComputerName", "InstanceName", "SqlInstance")
            ($results[0].PsObject.Properties.Name | Where-Object { $PSItem -in $ExpectedProps } | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should get test procedure: $procName" {
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }

        It "Should include system procedures" {
            ($results | Where-Object Name -eq "sp_columns") | Should -Not -BeNullOrEmpty
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no procs from master database" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase master
            $results.Database | Should -Not -Contain "master"
        }

        It "Should exclude system procedures" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -ExcludeSystemSp
            $results | Where-Object Name -eq "sp_helpdb" | Should -BeNullOrEmpty
        }
    }

    Context "Piping works" {
        It "Should allow piping from string" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbStoredProcedure -Database $db1Name
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }

        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1Name | Get-DbaDbStoredProcedure
            ($results | Where-Object Name -eq $procName).Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Search by name and schema" {
        It "Search by name" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbStoredProcedure -Database $db1Name -Name $procName
            $results.Name | Should -Be $procName
            $results.DatabaseId | Should -Be $db1.Id
        }

        It "Search by 2 part name" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbStoredProcedure -Database $db1Name -Name "$schemaName.$procName2"
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }

        It "Search by 3 part name and omit the -Database param" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbStoredProcedure -Name "$db1Name.$schemaName.$procName2"
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
            $results.Database | Should -Be $db1Name
        }

        It "Search by name and schema params" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbStoredProcedure -Database $db1Name -Name $procName2 -Schema $schemaName
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }

        It "Search by schema name" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbStoredProcedure -Database $db1Name -Schema $schemaName
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.StoredProcedure]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Schema",
                "ObjectId",
                "CreateDate",
                "DateLastModified",
                "Name",
                "ImplementationType",
                "Startup"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.StoredProcedure"
        }
    }
}