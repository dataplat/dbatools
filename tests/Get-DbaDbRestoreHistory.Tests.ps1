$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Since', 'RestoreType', 'Force', 'Last', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }

}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

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
    }
    Context "Preparation" {
        It "Should have prepared" {
            1 | Should -Be 1
        }
    }
    Context "Get last restore history for single database" {
        $results = @(Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname2 -Last)
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
        $results = @(Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2 -Last)
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
        $results = @(Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2)
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
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            $ExpectedPropsDefault = 'ComputerName,InstanceName,SqlInstance,Database,Username,RestoreType,Date,From,To,BackupFinishDate'.Split(',')
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
    Context "Get restore history by restore type" {
        It "returns the correct history records for full db restore" {
            $results = Get-DbaDbRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2 -RestoreType Database
            $results.count | Should -Be 4
            @($results | Where-Object RestoreType -eq Database).Count | Should -Be 4
        }
        It "returns the correct history records for diffential restore" {
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