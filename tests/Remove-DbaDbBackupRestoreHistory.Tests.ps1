param($ModuleName = 'dbatools')

Describe "Remove-DbaDbBackupRestoreHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbBackupRestoreHistory
        }

        It "has the required parameter: SqlInstance" -ForEach @("SqlInstance", "SqlCredential", "KeepDays", "Database", "InputObject", "EnableException") {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            # Setup code for all tests in this context
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $randomDb = "dbatoolsci_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $server -Name $randomDb
        }

        AfterAll {
            # Cleanup code after all tests in this context
            $null = Remove-DbaDatabase -SqlInstance $server -Database $randomDb -Confirm:$false
        }

        It "Removes backup history" {
            # Create some backup history
            $null = Backup-DbaDatabase -SqlInstance $server -Database $randomDb
            $null = Backup-DbaDatabase -SqlInstance $server -Database $randomDb -Type Differential
            $null = Backup-DbaDatabase -SqlInstance $server -Database $randomDb -Type Log

            # Check if history exists
            $initialHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $randomDb
            $initialHistory | Should -Not -BeNullOrEmpty

            # Remove history
            $result = Remove-DbaDbBackupRestoreHistory -SqlInstance $server -Database $randomDb -Confirm:$false

            # Verify history is removed
            $finalHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $randomDb
            $finalHistory | Should -BeNullOrEmpty

            # Check the result
            $result.Database | Should -Be $randomDb
            $result.Status | Should -Be "Succeeded"
        }

        It "Respects the KeepDays parameter" {
            # Create some backup history
            $null = Backup-DbaDatabase -SqlInstance $server -Database $randomDb
            Start-Sleep -Seconds 2
            $null = Backup-DbaDatabase -SqlInstance $server -Database $randomDb -Type Differential

            # Remove history but keep last day
            $result = Remove-DbaDbBackupRestoreHistory -SqlInstance $server -Database $randomDb -KeepDays 1 -Confirm:$false

            # Verify recent history is kept
            $remainingHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $randomDb
            $remainingHistory | Should -Not -BeNullOrEmpty
            $remainingHistory.Count | Should -Be 2

            # Check the result
            $result.Database | Should -Be $randomDb
            $result.Status | Should -Be "Succeeded"
        }
    }
}
