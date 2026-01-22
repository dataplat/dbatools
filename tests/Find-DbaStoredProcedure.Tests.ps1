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
                Database    = "Master"
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
                Database    = "Master"
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

    Context "Output Validation" {
        BeforeAll {
            # We want to run all commands in the setup with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatFind = @{
                SqlInstance = $TestConfig.InstanceSingle
                Pattern     = "dbatools*"
                Database    = "dbatoolsci_storedproceduredb"
            }
            $result = Find-DbaStoredProcedure @splatFind

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "SqlInstance",
                "Database",
                "DatabaseId",
                "Schema",
                "Name",
                "Owner",
                "IsSystemObject",
                "CreateDate",
                "LastModified",
                "StoredProcedureTextFound"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has StoredProcedure property available via Select-Object *" {
            $result.PSObject.Properties.Name | Should -Contain "StoredProcedure"
        }

        It "Has StoredProcedureFullText property available via Select-Object *" {
            $result.PSObject.Properties.Name | Should -Contain "StoredProcedureFullText"
        }
    }
}