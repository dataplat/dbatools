$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 39
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Start-DbaMigration).Parameters.Keys
        $knownParameters = 'Source', 'Destination', 'DetachAttach', 'Reattach', 'BackupRestore', 'NetworkShare', 'WithReplace', 'NoRecovery', 'SetSourceReadOnly', 'ReuseSourceFolderStructure', 'IncludeSupportDbs', 'SourceSqlCredential', 'DestinationSqlCredential', 'NoDatabases', 'NoLogins', 'NoAgentServer', 'NoCredentials', 'NoLinkedServers', 'NoSpConfigure', 'NoCentralManagementServer', 'NoDatabaseMail', 'NoSysDbUserObjects', 'NoSystemTriggers', 'NoBackupDevices', 'NoAudits', 'NoEndpoints', 'NoExtendedEvents', 'NoPolicyManagement', 'NoResourceGovernor', 'NoServerAuditSpecifications', 'NoCustomErrors', 'NoDataCollector', 'DisableJobsOnDestination', 'DisableJobsOnSource', 'NoSaRename', 'UseLastBackups', 'Continue', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>