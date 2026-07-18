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
    # NOTE ON COVERAGE: reading SSIS environment variables needs the SSIS Catalog (IntegrationServices)
    # SMO assemblies, available only on Windows PowerShell (Desktop) - live retrieval is DEFERRED-TO-GATE
    # (integrationPs51). What IS deterministic is the edition guard the source runs first: on PowerShell
    # Core the command refuses ($PSVersionTable.PSEdition -eq "Core"). This leg runs on the Core gate
    # (integrationPs7) where the guard fires; skipped on Desktop where the live retrieval is deferred.
    # Read-only command, no WhatiF. Probe-verified on Core.
    Context "Guarding on PowerShell Core" {
        It "Warns and returns nothing on PowerShell Core" -Skip:($PSVersionTable.PSEdition -ne "Core") {
            $splatCoreGuard = @{
                SqlInstance     = "dbatoolsci-core-guard"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Get-DbaSsisEnvironmentVariable @splatCoreGuard)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "This command is not supported on Linux or macOS"
        }
    }
}
