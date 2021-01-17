$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'StepName', 'NewName', 'Subsystem', 'SubSystemServer', 'Command', 'CmdExecSuccessCode', 'OnSuccessAction', 'OnSuccessStepId', 'OnFailAction', 'OnFailStepId', 'Database', 'DatabaseUser', 'RetryAttempts', 'RetryInterval', 'OutputFileName', 'Flag', 'ProxyName', 'EnableException', 'InputObject', 'Force'
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