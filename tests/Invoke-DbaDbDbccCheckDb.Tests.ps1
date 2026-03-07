#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDbccCheckDb",
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
                "NoIndex",
                "AllErrorMessages",
                "ExtendedLogicalChecks",
                "NoInformationalMessages",
                "TabLock",
                "EstimateOnly",
                "PhysicalOnly",
                "DataPurity",
                "MaxDop",
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
            SqlInstance = $TestConfig.InstanceSingle
        }
        $server = Connect-DbaInstance @splatConnection
        $random = Get-Random
        $dbname = "dbatoolsci_dbccCheckDb$random"

        $null = $server.Query("CREATE DATABASE $dbname")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Cmd",
                "Output"
            )

            $splatCheckDb = @{
                SqlInstance              = $TestConfig.InstanceSingle
                Database                 = $dbname
                NoInformationalMessages  = $true
            }
            $result = Invoke-DbaDbDbccCheckDb @splatCheckDb
        }

        foreach ($prop in $props) {
            It "Should return property: $prop" {
                $p = $result[0].PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }

        It "Returns correct database name" {
            $result.Database | Should -Contain $dbname
        }

        It "Returns correct command" {
            $result.Cmd | Should -Match "DBCC CHECKDB"
        }
    }

    Context "Validate PhysicalOnly option" {
        BeforeAll {
            $splatPhysical = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $dbname
                PhysicalOnly  = $true
            }
            $result = Invoke-DbaDbDbccCheckDb @splatPhysical
        }

        It "Should include PHYSICAL_ONLY in the command" {
            $result.Cmd | Should -Match "PHYSICAL_ONLY"
        }
    }

    Context "Validate NoIndex option" {
        BeforeAll {
            $splatNoIndex = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbname
                NoIndex     = $true
            }
            $result = Invoke-DbaDbDbccCheckDb @splatNoIndex
        }

        It "Should include NOINDEX in the command" {
            $result.Cmd | Should -Match "NOINDEX"
        }
    }
}
