param($ModuleName = 'dbatools')

Describe "Get-DbaDbRestoreHistory Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbRestoreHistory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have Since as a parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type DateTime
        }
        It "Should have RestoreType as a parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreType -Type String
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have Last as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Get-DbaDbRestoreHistory Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $dbname1 = "dbatoolsci_restorehistory1_$random"
        $dbname2 = "dbatoolsci_restorehistory2_$random"
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1, $dbname2 | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname1 -DestinationFilePrefix $dbname1
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix $dbname2
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix "rsh_pre_$dbname2" -WithReplace
        $fullBackup = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -Type Full
        $diffBackup = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -Type Diff
        $logBackup = Backup-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -Type Log

        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $diffBackup.BackupPath, $logBackup.BackupPath -DatabaseName $dbname1 -WithReplace
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1, $dbname2 | Remove-DbaDatabase -Confirm:$false
        Remove-Item -Path $fullBackup.BackupPath -Force
        Remove-Item -Path $logBackup.BackupPath -Force
    }

    Context "Get last restore history for single database" {
        BeforeAll {
            $results = @(Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname2 -Last)
        }
        It "Results holds 1 object" {
            $results.count | Should -Be 1
        }
        It "Should return the full restore with the correct properties" {
            $results[0].RestoreType | Should -Be "Database"
            $results[0].From | Should -Be $script:appveyorlabrepo\singlerestore\singlerestore.bak
            $results[0].To | Should -Match "\\rsh_pre_$dbname2"
        }
    }

    Context "Get last restore history for multiple database" {
        BeforeAll {
            $results = @(Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2 -Last)
        }
        It "Results holds 2 objects" {
            $results.count | Should -Be 2
        }
        It "Should return the full restore with the correct properties" {
            $results[0].RestoreType | Should -Be "Database"
            $results[1].RestoreType | Should -Be "Log"
            $results[0].From | Should -Be $script:appveyorlabrepo\singlerestore\singlerestore.bak
            $results[1].From | Should -Be $logBackup.BackupPath
            ($results | Where-Object Database -eq $dbname1).To | Should -Match "\\$dbname1"
            ($results | Where-Object Database -eq $dbname2).To | Should -Match "\\rsh_pre_$dbname2"
        }
    }

    Context "Get complete restore history for multiple database" {
        BeforeAll {
            $results = @(Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2)
        }
        It "Results holds correct number of objects" {
            $results.Count | Should -Be 6
        }
        It "Should return the full restore with the correct properties" {
            @($results | Where-Object Database -eq $dbname1).Count | Should -Be 4
            @($results | Where-Object Database -eq $dbname2).Count | Should -Be 2
        }
    }

    Context "return object properties" {
        It "has the correct properties" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2
            $result = $results[0]
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,Username,RestoreType,Date,From,To,first_lsn,last_lsn,checkpoint_lsn,database_backup_lsn,backup_finish_date,BackupFinishDate,RowError,RowState,Table,ItemArray,HasErrors'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
            $ExpectedPropsDefault = 'ComputerName,InstanceName,SqlInstance,Database,Username,RestoreType,Date,From,To,BackupFinishDate'.Split(',')
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }

    Context "Get restore history by restore type" {
        It "returns the correct history records for full db restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2 -RestoreType Database
            $results.count | Should -Be 4
            @($results | Where-Object RestoreType -eq Database).Count | Should -Be 4
        }
        It "returns the correct history records for differential restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1 -RestoreType Differential
            $results.Database | Should -Be $dbname1
            $results.RestoreType | Should -Be Differential
        }
        It "returns the correct history records for log restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1 -RestoreType Log
            $results.Database | Should -Be $dbname1
            $results.RestoreType | Should -Be Log
        }
    }
}
