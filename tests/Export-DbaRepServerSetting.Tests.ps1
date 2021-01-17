$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Add-Type -Path "$(Split-Path (Get-Module dbatools).Path)\bin\smo\Microsoft.SqlServer.Replication.dll" -ErrorAction Stop
Add-Type -Path "$(Split-Path (Get-Module dbatools).Path)\bin\smo\Microsoft.SqlServer.Rmo.dll" -ErrorAction Stop

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'FilePath', 'ScriptOption', 'InputObject', 'Encoding', 'Passthru', 'NoClobber', 'Append', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>