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
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:($PSVersionTable.PSEdition -eq "Core") {
        BeforeAll {
            $result = Get-DbaSsisEnvironmentVariable -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no SSIS environments configured on test instance" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no SSIS environments configured on test instance" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Folder", "Environment", "Id", "Name", "Description", "Type", "IsSensitive", "BaseDataType", "Value")
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}