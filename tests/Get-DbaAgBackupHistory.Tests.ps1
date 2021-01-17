$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Database', 'ExcludeDatabase', 'IncludeCopyOnly', 'Force', 'Since', 'RecoveryFork', 'Last', 'LastFull', 'LastDiff', 'LastLog', 'DeviceType', 'Raw', 'LastLsn', 'Type', 'EnableException', 'IncludeMirror'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor