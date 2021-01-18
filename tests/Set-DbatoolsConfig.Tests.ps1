$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Import-Module ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\bin', 'dbatools.dll'))

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'FullName', 'Module', 'Name', 'Value', 'PersistedValue', 'PersistedType', 'Description', 'Validation', 'Handler', 'Hidden', 'Default', 'Initialize', 'SimpleExport', 'ModuleExport', 'DisableValidation', 'DisableHandler', 'PassThru', 'Register', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Cmdlet')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    It "impacts the connection timeout" {
        $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60
        $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
        $results | Should -Match 'Connect Timeout=60'
    }
}