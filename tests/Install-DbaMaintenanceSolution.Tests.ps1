param($ModuleName = 'dbatools')

Describe "Install-DbaMaintenanceSolution" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaMaintenanceSolution
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have BackupLocation parameter" {
            $CommandUnderTest | Should -HaveParameter BackupLocation
        }
        It "Should have CleanupTime parameter" {
            $CommandUnderTest | Should -HaveParameter CleanupTime
        }
        It "Should have OutputFileDirectory parameter" {
            $CommandUnderTest | Should -HaveParameter OutputFileDirectory
        }
        It "Should have ReplaceExisting parameter" {
            $CommandUnderTest | Should -HaveParameter ReplaceExisting
        }
        It "Should have LogToTable parameter" {
            $CommandUnderTest | Should -HaveParameter LogToTable
        }
        It "Should have Solution parameter" {
            $CommandUnderTest | Should -HaveParameter Solution
        }
        It "Should have InstallJobs parameter" {
            $CommandUnderTest | Should -HaveParameter InstallJobs
        }
        It "Should have AutoScheduleJobs parameter" {
            $CommandUnderTest | Should -HaveParameter AutoScheduleJobs
        }
        It "Should have StartTime parameter" {
            $CommandUnderTest | Should -HaveParameter StartTime
        }
        It "Should have LocalFile parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have InstallParallel parameter" {
            $CommandUnderTest | Should -HaveParameter InstallParallel
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
