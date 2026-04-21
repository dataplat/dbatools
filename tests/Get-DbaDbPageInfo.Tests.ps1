#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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

    InModuleScope dbatools {
        Context "Table name normalization" {
            BeforeAll {
                $script:lastQuery = $null
                $script:mockDatabase = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database
                $script:mockDatabase.Name = "db1"
                $script:mockDatabase | Add-Member -Force -MemberType NoteProperty -Name Parent -Value ([PSCustomObject]@{
                        VersionMajor = 16
                    })
                $script:mockDatabase | Add-Member -Force -MemberType ScriptMethod -Name ExecuteWithResults -Value {
                    param($Sql)
                    $script:lastQuery = $Sql
                    [PSCustomObject]@{
                        Tables = @(@())
                    }
                }

                $script:mockServer = [DbaInstanceParameter]"sql1"
                $script:mockServer | Add-Member -Force -MemberType NoteProperty -Name Databases -Value @($script:mockDatabase)

                Mock Connect-DbaInstance { $script:mockServer }
            }

            It "honors schema-qualified -Table input" {
                $script:lastQuery = $null

                $null = Get-DbaDbPageInfo -SqlInstance "sql1" -Database "db1" -Table "db1.sales.Customer"
                $normalizedQuery = $script:lastQuery -replace "\s+", " "

                $normalizedQuery | Should -Match "st\.name = N'Customer'\s+AND\s+ss\.name = N'sales'\s+AND\s+DB_NAME\(\) = N'db1'"
                $normalizedQuery | Should -Not -Match "st\.name IN"
            }
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
    Context "Count Pages" {
        It "returns the proper results" {
            $result = Get-DbaDbPageInfo -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            @($result).Count | Should -Be 9
            @($result | Where-Object IsAllocated -eq $false).Count | Should -Be 5
            @($result | Where-Object IsAllocated -eq $true).Count | Should -Be 4
        }
    }
}