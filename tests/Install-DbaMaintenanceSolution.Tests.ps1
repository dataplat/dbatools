$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'BackupLocation', 'CleanupTime', 'OutputFileDirectory', 'ReplaceExisting', 'LogToTable', 'Solution', 'InstallJobs', 'LocalFile', 'Force', 'InstallParallel', 'EnableException', 'AutoScheduleJobs', 'StartTime'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Limited testing of Maintenance Solution installer" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Databases['tempdb'].Query("CREATE TABLE CommandLog (id int)")
        }
        AfterAll {
            $server.Databases['tempdb'].Query("DROP TABLE CommandLog")
            Invoke-DbaQuery -SqlInstance $TestConfig.instance3 -Database tempdb -Query "drop procedure CommandExecute; drop procedure DatabaseBackup; drop procedure DatabaseIntegrityCheck; drop procedure IndexOptimize;"
        }
        It "does not overwrite existing " {
            $results = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.instance2 -Database tempdb -WarningVariable WarnVar -WarningAction SilentlyContinue
            $WarnVar | Should -Match "already exists"
        }

        It "Continues the installation on other servers " {
            $results2 = Install-DbaMaintenanceSolution -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database tempdb -WarningAction SilentlyContinue
            $sproc = Get-DbaModule -SqlInstance $TestConfig.instance3 -Database tempdb | Where-Object { $_.Name -eq "CommandExecute" }
            $sproc | Should -Not -BeNullOrEmpty
        }
    }
}