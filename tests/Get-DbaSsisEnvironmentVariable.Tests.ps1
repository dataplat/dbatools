$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Environment', 'EnvironmentExclude', 'Folder', 'FolderExclude', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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