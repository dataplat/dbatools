#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaBinaryFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "Schema",
                "FilePath",
                "EnableException",
                "Statement",
                "NoFileNameColumn",
                "BinaryColumn",
                "FileNameColumn",
                "InputObject",
                "Path"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testDbConnection = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database tempdb
        $null = $testDbConnection.Query("CREATE TABLE [dbo].[BunchOFiles]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $null = $testDbConnection.Query("DROP TABLE dbo.BunchOFiles")
        } catch {
            $null = 1
        }

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    It "imports files into table data" {
        $importResults = Import-DbaBinaryFile -SqlInstance $TestConfig.instance2 -Database tempdb -Table BunchOFiles -FilePath "$($TestConfig.appveyorlabrepo)\azure\adalsql.msi" -WarningAction Continue -ErrorAction Stop -EnableException
        $importResults.Database | Should -Be "tempdb"
        $importResults.FilePath | Should -match "adalsql.msi"
    }

    It "imports files into table data from piped" {
        $pipeResults = Get-ChildItem -Path "$($TestConfig.appveyorlabrepo)\certificates" | Import-DbaBinaryFile -SqlInstance $TestConfig.instance2 -Database tempdb -Table BunchOFiles -WarningAction Continue -ErrorAction Stop -EnableException
        $pipeResults.Database | Should -Be @("tempdb", "tempdb")
        Split-Path -Path $pipeResults.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
    }

    It "piping from Get-DbaBinaryFileTable works" {
        $fileTableResults = Get-DbaBinaryFileTable -SqlInstance $TestConfig.instance2 -Database tempdb -Table BunchOFiles | Import-DbaBinaryFile -WarningAction Continue -ErrorAction Stop -EnableException -Path "$($TestConfig.appveyorlabrepo)\certificates"
        $fileTableResults.Database | Should -Be @("tempdb", "tempdb")
        Split-Path -Path $fileTableResults.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
    }
}