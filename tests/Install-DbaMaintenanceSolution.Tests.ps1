param($ModuleName = 'dbatools')

Describe "Install-DbaMaintenanceSolution" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaMaintenanceSolution
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "BackupLocation",
                "CleanupTime",
                "OutputFileDirectory",
                "ReplaceExisting",
                "LogToTable",
                "Solution",
                "InstallJobs",
                "AutoScheduleJobs",
                "StartTime",
                "LocalFile",
                "Force",
                "InstallParallel",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Limited testing of Maintenance Solution installer" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Databases['tempdb'].Query("CREATE TABLE CommandLog (id int)")
        }
        AfterAll {
            $server.Databases['tempdb'].Query("DROP TABLE CommandLog")
            Invoke-DbaQuery -SqlInstance $global:instance3 -Database tempdb -Query "drop procedure CommandExecute; drop procedure DatabaseBackup; drop procedure DatabaseIntegrityCheck; drop procedure IndexOptimize;"
        }
        It "does not overwrite existing" {
            $warn = $null
            $results = Install-DbaMaintenanceSolution -SqlInstance $global:instance2 -Database tempdb -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Match "already exists"
        }

        It "Continues the installation on other servers" {
            $results2 = Install-DbaMaintenanceSolution -SqlInstance $global:instance2, $global:instance3 -Database tempdb
            $sproc = Get-DbaDbModule -SqlInstance $global:instance3 -Database tempdb | Where-Object { $_.Name -eq "CommandExecute" }
            $sproc | Should -Not -BeNullOrEmpty
        }
    }
}
