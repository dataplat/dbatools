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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Check if SSISDB exists on the test instance
        $ssisDb = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database SSISDB -ErrorAction SilentlyContinue
        $global:skipSsis = ($null -eq $ssisDb)

        if (-not $global:skipSsis) {
            $testFolder = "dbatoolsci_folder_$(Get-Random)"
            $testEnv = "dbatoolsci_env_$(Get-Random)"
            $testVar = "dbatoolsci_var_$(Get-Random)"

            # Create folder, environment, and variable for testing
            $splatSetup = @{
                SqlInstance = $TestConfig.instance1
                Database    = "SSISDB"
                Query       = @"
DECLARE @folder_id bigint;
EXEC [SSISDB].[catalog].[create_folder] @folder_name = N'$testFolder', @folder_id = @folder_id OUTPUT;
EXEC [SSISDB].[catalog].[create_environment] @folder_name = N'$testFolder', @environment_name = N'$testEnv';
EXEC [SSISDB].[catalog].[create_environment_variable]
    @folder_name = N'$testFolder',
    @environment_name = N'$testEnv',
    @variable_name = N'$testVar',
    @data_type = N'String',
    @sensitive = 0,
    @value = N'TestValue';
"@
            }
            $null = Invoke-DbaQuery @splatSetup
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not $global:skipSsis) {
            $splatCleanup = @{
                SqlInstance = $TestConfig.instance1
                Database    = "SSISDB"
                Query       = "EXEC [SSISDB].[catalog].[delete_folder] @folder_name = N'$testFolder'"
            }
            $null = Invoke-DbaQuery @splatCleanup -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When getting SSIS environment variables" -Skip:$global:skipSsis {
        It "Should return environment variables" {
            $splatGetVars = @{
                SqlInstance = $TestConfig.instance1
                Folder      = $testFolder
                Environment = $testEnv
            }
            $result = Get-DbaSsisEnvironmentVariable @splatGetVars -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Contain $testVar
            $result.Value | Should -Contain "TestValue"
        }
    }

    Context "Output validation" -Skip:$global:skipSsis {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}