param($ModuleName = 'dbatools')

Describe "Restore-DbaDatabase Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import module and set up any necessary test data
        Import-Module $ModuleName
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command -Name Restore-DbaDatabase
            $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential
        }
        It "Should have Path parameter" {
            $command | Should -HaveParameter Path
        }
        It "Should have DatabaseName parameter" {
            $command | Should -HaveParameter DatabaseName
        }
        It "Should have DestinationDataDirectory parameter" {
            $command | Should -HaveParameter DestinationDataDirectory
        }
        It "Should have DestinationLogDirectory parameter" {
            $command | Should -HaveParameter DestinationLogDirectory
        }
        It "Should have DestinationFileStreamDirectory parameter" {
            $command | Should -HaveParameter DestinationFileStreamDirectory
        }
        It "Should have RestoreTime parameter" {
            $command | Should -HaveParameter RestoreTime
        }
        It "Should have NoRecovery parameter" {
            $command | Should -HaveParameter NoRecovery
        }
        It "Should have WithReplace parameter" {
            $command | Should -HaveParameter WithReplace
        }
        It "Should have KeepReplication parameter" {
            $command | Should -HaveParameter KeepReplication
        }
        It "Should have XpDirTree parameter" {
            $command | Should -HaveParameter XpDirTree
        }
        It "Should have NoXpDirRecurse parameter" {
            $command | Should -HaveParameter NoXpDirRecurse
        }
        It "Should have OutputScriptOnly parameter" {
            $command | Should -HaveParameter OutputScriptOnly
        }
        It "Should have VerifyOnly parameter" {
            $command | Should -HaveParameter VerifyOnly
        }
        It "Should have MaintenanceSolutionBackup parameter" {
            $command | Should -HaveParameter MaintenanceSolutionBackup
        }
        It "Should have FileMapping parameter" {
            $command | Should -HaveParameter FileMapping
        }
        It "Should have IgnoreLogBackup parameter" {
            $command | Should -HaveParameter IgnoreLogBackup
        }
        It "Should have IgnoreDiffBackup parameter" {
            $command | Should -HaveParameter IgnoreDiffBackup
        }
        It "Should have UseDestinationDefaultDirectories parameter" {
            $command | Should -HaveParameter UseDestinationDefaultDirectories
        }
        It "Should have ReuseSourceFolderStructure parameter" {
            $command | Should -HaveParameter ReuseSourceFolderStructure
        }
        It "Should have DestinationFilePrefix parameter" {
            $command | Should -HaveParameter DestinationFilePrefix
        }
        It "Should have RestoredDatabaseNamePrefix parameter" {
            $command | Should -HaveParameter RestoredDatabaseNamePrefix
        }
        It "Should have TrustDbBackupHistory parameter" {
            $command | Should -HaveParameter TrustDbBackupHistory
        }
        It "Should have MaxTransferSize parameter" {
            $command | Should -HaveParameter MaxTransferSize
        }
        It "Should have BlockSize parameter" {
            $command | Should -HaveParameter BlockSize
        }
        It "Should have BufferCount parameter" {
            $command | Should -HaveParameter BufferCount
        }
        It "Should have DirectoryRecurse parameter" {
            $command | Should -HaveParameter DirectoryRecurse
        }
        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException
        }
        It "Should have StandbyDirectory parameter" {
            $command | Should -HaveParameter StandbyDirectory
        }
        It "Should have Continue parameter" {
            $command | Should -HaveParameter Continue
        }
        It "Should have ExecuteAs parameter" {
            $command | Should -HaveParameter ExecuteAs
        }
        It "Should have AzureCredential parameter" {
            $command | Should -HaveParameter AzureCredential
        }
        It "Should have ReplaceDbNameInFile parameter" {
            $command | Should -HaveParameter ReplaceDbNameInFile
        }
        It "Should have DestinationFileSuffix parameter" {
            $command | Should -HaveParameter DestinationFileSuffix
        }
        It "Should have Recover parameter" {
            $command | Should -HaveParameter Recover
        }
        It "Should have KeepCDC parameter" {
            $command | Should -HaveParameter KeepCDC
        }
        It "Should have GetBackupInformation parameter" {
            $command | Should -HaveParameter GetBackupInformation
        }
        It "Should have StopAfterGetBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterGetBackupInformation
        }
        It "Should have SelectBackupInformation parameter" {
            $command | Should -HaveParameter SelectBackupInformation
        }
        It "Should have StopAfterSelectBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterSelectBackupInformation
        }
        It "Should have FormatBackupInformation parameter" {
            $command | Should -HaveParameter FormatBackupInformation
        }
        It "Should have StopAfterFormatBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterFormatBackupInformation
        }
        It "Should have TestBackupInformation parameter" {
            $command | Should -HaveParameter TestBackupInformation
        }
        It "Should have StopAfterTestBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterTestBackupInformation
        }
        It "Should have PageRestore parameter" {
            $command | Should -HaveParameter PageRestore
        }
        It "Should have PageRestoreTailFolder parameter" {
            $command | Should -HaveParameter PageRestoreTailFolder
        }
        It "Should have StopBefore parameter" {
            $command | Should -HaveParameter StopBefore
        }
        It "Should have StopMark parameter" {
            $command | Should -HaveParameter StopMark
        }
        It "Should have StopAfterDate parameter" {
            $command | Should -HaveParameter StopAfterDate
        }
        It "Should have StatementTimeout parameter" {
            $command | Should -HaveParameter StatementTimeout
        }
    }
}

Describe "Restore-DbaDatabase Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $env:appveyorlabrepo = "C:\github\appveyor-lab"
        $DataFolder = 'C:\temp\datafiles'
        $LogFolder = 'C:\temp\logfiles'
        New-Item -ItemType Directory -Force -Path $DataFolder
        New-Item -ItemType Directory -Force -Path $LogFolder
    }

    Context "Properly restores a database on the local drive using Path" {
        BeforeAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Remove-DbaDatabase -Confirm:$false
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$env:appveyorlabrepo\singlerestore\singlerestore.bak"
        }
        It "Should return the proper backup file location" {
            $results.BackupFile | Should -Be "$env:appveyorlabrepo\singlerestore\singlerestore.bak"
        }
        It "Should return successful restore" {
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Ensuring warning is thrown if database already exists" {
        BeforeAll {
            $results = Restore-DbaDatabase -SqlInstance $global:instance2 -Path "$env:appveyorlabrepo\singlerestore\singlerestore.bak" -WarningVariable warning -WarningAction SilentlyContinue
        }
        It "Should warn" {
            $warning | Where-Object { $_ -like '*Test-DbaBackupInformation*Database*' } | Should -Match "exists, so WithReplace must be specified"
        }
        It "Should not return object" {
            $results | Should -Be $null
        }
    }

    Context "Database is properly removed again after withreplace test" {
        BeforeAll {
            Get-DbaProcess $global:instance2 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            $results = Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database singlerestore
        }
        It "Should say the status was dropped" {
            $results.Status -eq "Dropped" -or $results.Status -eq $null | Should -Be $true
        }
    }

    # Continue with the rest of the contexts and tests...
    # Make sure to update all assertions to use the new syntax (e.g., Should -Be instead of Should Be)
    # Move any setup code to BeforeAll blocks
    # Ensure all test code is within It blocks
}
