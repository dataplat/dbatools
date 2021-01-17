$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'BackupLocation', 'CleanupTime', 'OutputFileDirectory', 'ReplaceExisting', 'LogToTable', 'Solution', 'InstallJobs', 'LocalFile', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Limited testing of Maintenance Solution installer" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Databases['tempdb'].Query("CREATE TABLE CommandLog (id int)")
        }
        AfterAll {
            $server.Databases['tempdb'].Query("DROP TABLE CommandLog")
        }
        It "does not overwrite existing " {
            $results = Install-DbaMaintenanceSolution -SqlInstance $script:instance2 -Database tempdb -WarningVariable warn -WarningAction SilentlyContinue
            $warn -match "already exists" | Should Be $true
        }
    }
}
