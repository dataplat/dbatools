$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'BackupLocation', 'CleanupTime', 'OutputFileDirectory', 'ReplaceExisting', 'LogToTable', 'Solution', 'InstallJobs', 'LocalFile', 'Force', 'InstallParallel', 'EnableException'

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
            Invoke-DbaQuery -SqlInstance $script:instance3 -Database tempdb -Query "drop procedure CommandExecute; drop procedure DatabaseBackup; drop procedure DatabaseIntegrityCheck; drop procedure IndexOptimize;"
        }
        It "does not overwrite existing " {
            $results = Install-DbaMaintenanceSolution -SqlInstance $script:instance2 -Database tempdb -WarningVariable warn -WarningAction SilentlyContinue
            $warn -match "already exists" | Should Be $true
        }

        It "Continues the installation on other servers " {
            $results2 = Install-DbaMaintenanceSolution -SqlInstance $script:instance2, $script:instance3 -Database tempdb
            $sproc = Get-DbaDbModule -SqlInstance $script:instance3 -Database tempdb | Where-Object {$_.Name -eq "CommandExecute"}
            $sproc | Should -Not -BeNullOrEmpty
        }
    }
}
