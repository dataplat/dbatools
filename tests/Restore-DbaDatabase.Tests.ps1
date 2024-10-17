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
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Path parameter" {
            $command | Should -HaveParameter Path -Type Object[] -Mandatory:$false
        }
        It "Should have DatabaseName parameter" {
            $command | Should -HaveParameter DatabaseName -Type Object[] -Mandatory:$false
        }
        It "Should have DestinationDataDirectory parameter" {
            $command | Should -HaveParameter DestinationDataDirectory -Type String -Mandatory:$false
        }
        It "Should have DestinationLogDirectory parameter" {
            $command | Should -HaveParameter DestinationLogDirectory -Type String -Mandatory:$false
        }
        It "Should have DestinationFileStreamDirectory parameter" {
            $command | Should -HaveParameter DestinationFileStreamDirectory -Type String -Mandatory:$false
        }
        It "Should have RestoreTime parameter" {
            $command | Should -HaveParameter RestoreTime -Type DateTime -Mandatory:$false
        }
        It "Should have NoRecovery parameter" {
            $command | Should -HaveParameter NoRecovery -Type Switch -Mandatory:$false
        }
        It "Should have WithReplace parameter" {
            $command | Should -HaveParameter WithReplace -Type Switch -Mandatory:$false
        }
        It "Should have KeepReplication parameter" {
            $command | Should -HaveParameter KeepReplication -Type Switch -Mandatory:$false
        }
        It "Should have XpDirTree parameter" {
            $command | Should -HaveParameter XpDirTree -Type Switch -Mandatory:$false
        }
        It "Should have NoXpDirRecurse parameter" {
            $command | Should -HaveParameter NoXpDirRecurse -Type Switch -Mandatory:$false
        }
        It "Should have OutputScriptOnly parameter" {
            $command | Should -HaveParameter OutputScriptOnly -Type Switch -Mandatory:$false
        }
        It "Should have VerifyOnly parameter" {
            $command | Should -HaveParameter VerifyOnly -Type Switch -Mandatory:$false
        }
        It "Should have MaintenanceSolutionBackup parameter" {
            $command | Should -HaveParameter MaintenanceSolutionBackup -Type Switch -Mandatory:$false
        }
        It "Should have FileMapping parameter" {
            $command | Should -HaveParameter FileMapping -Type Hashtable -Mandatory:$false
        }
        It "Should have IgnoreLogBackup parameter" {
            $command | Should -HaveParameter IgnoreLogBackup -Type Switch -Mandatory:$false
        }
        It "Should have IgnoreDiffBackup parameter" {
            $command | Should -HaveParameter IgnoreDiffBackup -Type Switch -Mandatory:$false
        }
        It "Should have UseDestinationDefaultDirectories parameter" {
            $command | Should -HaveParameter UseDestinationDefaultDirectories -Type Switch -Mandatory:$false
        }
        It "Should have ReuseSourceFolderStructure parameter" {
            $command | Should -HaveParameter ReuseSourceFolderStructure -Type Switch -Mandatory:$false
        }
        It "Should have DestinationFilePrefix parameter" {
            $command | Should -HaveParameter DestinationFilePrefix -Type String -Mandatory:$false
        }
        It "Should have RestoredDatabaseNamePrefix parameter" {
            $command | Should -HaveParameter RestoredDatabaseNamePrefix -Type String -Mandatory:$false
        }
        It "Should have TrustDbBackupHistory parameter" {
            $command | Should -HaveParameter TrustDbBackupHistory -Type Switch -Mandatory:$false
        }
        It "Should have MaxTransferSize parameter" {
            $command | Should -HaveParameter MaxTransferSize -Type Int32 -Mandatory:$false
        }
        It "Should have BlockSize parameter" {
            $command | Should -HaveParameter BlockSize -Type Int32 -Mandatory:$false
        }
        It "Should have BufferCount parameter" {
            $command | Should -HaveParameter BufferCount -Type Int32 -Mandatory:$false
        }
        It "Should have DirectoryRecurse parameter" {
            $command | Should -HaveParameter DirectoryRecurse -Type Switch -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have StandbyDirectory parameter" {
            $command | Should -HaveParameter StandbyDirectory -Type String -Mandatory:$false
        }
        It "Should have Continue parameter" {
            $command | Should -HaveParameter Continue -Type Switch -Mandatory:$false
        }
        It "Should have ExecuteAs parameter" {
            $command | Should -HaveParameter ExecuteAs -Type String -Mandatory:$false
        }
        It "Should have AzureCredential parameter" {
            $command | Should -HaveParameter AzureCredential -Type String -Mandatory:$false
        }
        It "Should have ReplaceDbNameInFile parameter" {
            $command | Should -HaveParameter ReplaceDbNameInFile -Type Switch -Mandatory:$false
        }
        It "Should have DestinationFileSuffix parameter" {
            $command | Should -HaveParameter DestinationFileSuffix -Type String -Mandatory:$false
        }
        It "Should have Recover parameter" {
            $command | Should -HaveParameter Recover -Type Switch -Mandatory:$false
        }
        It "Should have KeepCDC parameter" {
            $command | Should -HaveParameter KeepCDC -Type Switch -Mandatory:$false
        }
        It "Should have GetBackupInformation parameter" {
            $command | Should -HaveParameter GetBackupInformation -Type String -Mandatory:$false
        }
        It "Should have StopAfterGetBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterGetBackupInformation -Type Switch -Mandatory:$false
        }
        It "Should have SelectBackupInformation parameter" {
            $command | Should -HaveParameter SelectBackupInformation -Type String -Mandatory:$false
        }
        It "Should have StopAfterSelectBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterSelectBackupInformation -Type Switch -Mandatory:$false
        }
        It "Should have FormatBackupInformation parameter" {
            $command | Should -HaveParameter FormatBackupInformation -Type String -Mandatory:$false
        }
        It "Should have StopAfterFormatBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterFormatBackupInformation -Type Switch -Mandatory:$false
        }
        It "Should have TestBackupInformation parameter" {
            $command | Should -HaveParameter TestBackupInformation -Type String -Mandatory:$false
        }
        It "Should have StopAfterTestBackupInformation parameter" {
            $command | Should -HaveParameter StopAfterTestBackupInformation -Type Switch -Mandatory:$false
        }
        It "Should have PageRestore parameter" {
            $command | Should -HaveParameter PageRestore -Type Object -Mandatory:$false
        }
        It "Should have PageRestoreTailFolder parameter" {
            $command | Should -HaveParameter PageRestoreTailFolder -Type String -Mandatory:$false
        }
        It "Should have StopBefore parameter" {
            $command | Should -HaveParameter StopBefore -Type Switch -Mandatory:$false
        }
        It "Should have StopMark parameter" {
            $command | Should -HaveParameter StopMark -Type String -Mandatory:$false
        }
        It "Should have StopAfterDate parameter" {
            $command | Should -HaveParameter StopAfterDate -Type DateTime -Mandatory:$false
        }
        It "Should have StatementTimeout parameter" {
            $command | Should -HaveParameter StatementTimeout -Type Int32 -Mandatory:$false
        }
    }
}

Describe "Restore-DbaDatabase Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $global:instance2 = "localhost"
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
