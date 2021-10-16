$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'UseWindowsCredentials', 'OverrideExplicitCredential', 'OverrideConnectionPolicy', 'DisabledConnectionTypes', 'DisableBadCredentialCache', 'DisableCimPersistence', 'DisableCredentialAutoRegister', 'EnableCredentialFailover', 'WindowsCredentialsAreBad', 'CimWinRMOptions', 'CimDCOMOptions', 'AddBadCredential', 'RemoveBadCredential', 'ClearBadCredential', 'ClearCredential', 'ResetCredential', 'ResetConnectionStatus', 'ResetConfiguration', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}