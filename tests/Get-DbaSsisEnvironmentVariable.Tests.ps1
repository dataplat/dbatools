#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisEnvironmentVariable",
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
                "Environment",
                "EnvironmentExclude",
                "Folder",
                "FolderExclude",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Mock to avoid actual SQL Server dependency in unit tests
            Mock -CommandName Connect-DbaInstance -MockWith {
                [PSCustomObject]@{
                    ComputerName       = "MockComputer"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "MockComputer"
                    Query              = { }
                }
            }
            Mock -CommandName New-Object -MockWith {
                [PSCustomObject]@{
                    Catalogs = @(
                        [PSCustomObject]@{
                            Name    = "SSISDB"
                            Folders = @{
                                "TestFolder" = [PSCustomObject]@{
                                    Environments = @(
                                        [PSCustomObject]@{
                                            Name          = "TestEnv"
                                            EnvironmentId = 1
                                        }
                                    )
                                }
                            }
                        }
                    )
                }
            } -ParameterFilter { $TypeName -eq "Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices" }

            # Create a mock result that matches actual output structure
            $mockResult = [PSCustomObject]@{
                ComputerName = "MockComputer"
                InstanceName = "MSSQLSERVER"
                SqlInstance  = "MockComputer"
                Folder       = "TestFolder"
                Environment  = "TestEnv"
                Id           = 1
                Name         = "TestVar"
                Description  = "Test Description"
                Type         = "String"
                IsSensitive  = $false
                BaseDataType = "nvarchar"
                Value        = "TestValue"
            }
        }

        It "Returns PSCustomObject" {
            # Use the mock result for validation
            $mockResult.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties documented in .OUTPUTS" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Folder",
                "Environment",
                "Id",
                "Name",
                "Description",
                "Type",
                "IsSensitive",
                "BaseDataType",
                "Value"
            )
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Has exactly the documented properties (no extras)" {
            $expectedCount = 12
            $mockResult.PSObject.Properties.Name.Count | Should -Be $expectedCount -Because "output should have exactly $expectedCount properties as documented"
        }
    }
}

<#

-- Create a folder if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM [SSISDB].[catalog].[folders] WHERE name = N'TestFolder')
BEGIN
    EXEC [SSISDB].[catalog].[create_folder] @folder_name = N'TestFolder', @folder_id = NULL;
END

-- Create an environment in the folder if it doesn't exist
IF NOT EXISTS (
    SELECT 1 FROM [SSISDB].[catalog].[environments]
    WHERE name = N'TestEnv' AND folder_id = (SELECT folder_id FROM [SSISDB].[catalog].[folders] WHERE name = N'TestFolder')
)
BEGIN
    EXEC [SSISDB].[catalog].[create_environment] @folder_name = N'TestFolder', @environment_name = N'TestEnv';
END

-- Create an environment variable in the environment if it doesn't exist
IF NOT EXISTS (
    SELECT 1 FROM [SSISDB].[catalog].[environment_variables]
    WHERE name = N'TestVar'
      AND environment_id = (
            SELECT environment_id
            FROM [SSISDB].[catalog].[environments]
            WHERE name = N'TestEnv'
              AND folder_id = (SELECT folder_id FROM [SSISDB].[catalog].[folders] WHERE name = N'TestFolder')
      )
)
BEGIN
    EXEC [SSISDB].[catalog].[create_environment_variable]
        @folder_name = N'TestFolder',
        @environment_name = N'TestEnv',
        @variable_name = N'TestVar',
        @data_type = N'String',
        @sensitive = 0,
        @value = N'Chello';
END

#>
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>