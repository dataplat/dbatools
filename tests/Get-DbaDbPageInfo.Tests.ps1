#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbPageInfo",
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
                "Schema",
                "Table",
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

        $random = Get-Random
        $dbname = "dbatoolsci_pageinfo_$random"

        # Clean up any existing connections
        $splatStopProcess = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Program         = "dbatools PowerShell module - dbatools.io"
            WarningAction   = "SilentlyContinue"
            EnableException = $true
        }
        Get-DbaProcess @splatStopProcess | Stop-DbaProcess -WarningAction SilentlyContinue

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("CREATE DATABASE $dbname;")
        $server.Databases[$dbname].Query("CREATE TABLE [dbo].[TestTable](TestText VARCHAR(MAX) NOT NULL)")
        $query = "
                INSERT INTO dbo.TestTable
                (
                    TestText
                )
                VALUES
                ('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"

        # Generate a bunch of extra inserts to create enough pages
        1..100 | ForEach-Object {
            $query += ",('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"
        }
        $server.Databases[$dbname].Query($query)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbPageInfo -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.Data.DataRow]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Schema',
                'Table',
                'PageType',
                'PageFreePercent',
                'IsAllocated',
                'IsMixedPage'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Count Pages" {
        It "returns the proper results" {
            $result = Get-DbaDbPageInfo -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            @($result).Count | Should -Be 9
            @($result | Where-Object IsAllocated -eq $false).Count | Should -Be 5
            @($result | Where-Object IsAllocated -eq $true).Count | Should -Be 4
        }
    }
}