#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaStoredProcedure",
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
                "Pattern",
                "IncludeSystemObjects",
                "IncludeSystemDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds Procedures in a System Database" {
        BeforeAll {
            # We want to run all commands in the setup with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $ServerProcedure = @"
CREATE PROCEDURE dbo.cp_dbatoolsci_sysadmin
AS
SET NOCOUNT ON;
SELECT [sid],[loginname],[sysadmin]
FROM [master].[sys].[syslogins];
"@
            $splatCreateProc = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
                Query       = $ServerProcedure
            }
            $null = Invoke-DbaQuery @splatCreateProc

            # We want to run the test command without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # Cleanup - We want to run all commands in the cleanup with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $DropProcedure = "DROP PROCEDURE dbo.cp_dbatoolsci_sysadmin;"
            $splatDropProc = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
                Query       = $DropProcedure
            }
            $null = Invoke-DbaQuery @splatDropProc

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find a specific StoredProcedure named cp_dbatoolsci_sysadmin" {
            $splatFind = @{
                SqlInstance            = $TestConfig.InstanceSingle
                Pattern                = "dbatools*"
                IncludeSystemDatabases = $true
            }
            $results = Find-DbaStoredProcedure @splatFind
            $results.Name | Should -Contain "cp_dbatoolsci_sysadmin"
        }
    }

    Context "Command finds Procedures in a User Database" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Set variables. They are available in all the It blocks.
            $testDbName = "dbatoolsci_storedproceduredb"

            # Create the database
            $splatNewDb = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $testDbName
            }
            $null = New-DbaDatabase @splatNewDb

            # Create stored procedure
            $StoredProcedure = @"
CREATE PROCEDURE dbo.sp_dbatoolsci_custom
AS
    SET NOCOUNT ON;
    PRINT 'Dbatools Rocks';
"@
            $splatCreateProc = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
                Query       = $StoredProcedure
            }
            $null = Invoke-DbaQuery @splatCreateProc

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "dbatoolsci_storedproceduredb"
            }
            $null = Remove-DbaDatabase @splatRemoveDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find a specific StoredProcedure named sp_dbatoolsci_custom" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Pattern     = "dbatools*"
                Database    = "dbatoolsci_storedproceduredb"
            }
            $results = Find-DbaStoredProcedure @splatFind
            $results.Name | Should -Contain "sp_dbatoolsci_custom"
        }

        It "Should find sp_dbatoolsci_custom in dbatoolsci_storedproceduredb" {
            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Pattern     = "dbatools*"
                Database    = "dbatoolsci_storedproceduredb"
            }
            $results = Find-DbaStoredProcedure @splatFind
            $results.Database | Should -Contain "dbatoolsci_storedproceduredb"
        }

        It "Should find no results when Excluding dbatoolsci_storedproceduredb" {
            $splatFind = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Pattern         = "dbatools*"
                ExcludeDatabase = "dbatoolsci_storedproceduredb"
            }
            $results = Find-DbaStoredProcedure @splatFind
            $results | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connection of the caller is left in the database it was in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_proc_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $contextDbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -Query "EXEC ('CREATE PROCEDURE dbo.dbatoolsci_proc AS SELECT 1');"

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $contextBefore = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $contextResult = Find-DbaStoredProcedure -SqlInstance $callerServer -Database $contextDbName -Pattern dbatoolsci

            $contextAfter = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still returns what it was asked for" {
            # Only a call that really runs can move the connection, so a command that returned nothing
            # would pass the assertion below for the wrong reason.
            $contextResult | Should -Not -BeNullOrEmpty
        }

        It "leaves the connection in the database it was in" {
            $contextAfter | Should -Be $contextBefore
        }
    }
}
