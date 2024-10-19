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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "DatabaseName",
                "DestinationDataDirectory",
                "DestinationLogDirectory",
                "DestinationFileStreamDirectory",
                "RestoreTime",
                "NoRecovery",
                "WithReplace",
                "KeepReplication",
                "XpDirTree",
                "NoXpDirRecurse",
                "OutputScriptOnly",
                "VerifyOnly",
                "MaintenanceSolutionBackup",
                "FileMapping",
                "IgnoreLogBackup",
                "IgnoreDiffBackup",
                "UseDestinationDefaultDirectories",
                "ReuseSourceFolderStructure",
                "DestinationFilePrefix",
                "RestoredDatabaseNamePrefix",
                "TrustDbBackupHistory",
                "MaxTransferSize",
                "BlockSize",
                "BufferCount",
                "DirectoryRecurse",
                "EnableException",
                "StandbyDirectory",
                "Continue",
                "ExecuteAs",
                "AzureCredential",
                "ReplaceDbNameInFile",
                "DestinationFileSuffix",
                "Recover",
                "KeepCDC",
                "GetBackupInformation",
                "StopAfterGetBackupInformation",
                "SelectBackupInformation",
                "StopAfterSelectBackupInformation",
                "FormatBackupInformation",
                "StopAfterFormatBackupInformation",
                "TestBackupInformation",
                "StopAfterTestBackupInformation",
                "PageRestore",
                "PageRestoreTailFolder",
                "StopBefore",
                "StopMark",
                "StopAfterDate",
                "StatementTimeout"
            )
            foreach ($param in $requiredParameters) {
                $command | Should -HaveParameter $param
            }
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
