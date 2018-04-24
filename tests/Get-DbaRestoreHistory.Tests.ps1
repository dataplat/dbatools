$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 8
        $commonParamCount = ([System.Management.Automation.PSCmdlet]::CommonParameters).Count
        [object[]]$params = (Get-ChildItem function:\Get-DbaRestoreHistory).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Since', 'Last', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $commonParamCount | Should Be $paramCount
        }
    }

}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $DestBackupDir = 'C:\Temp\backups'
        if (-Not(Test-Path $DestBackupDir)) {
            New-Item -Type Container -Path $DestBackupDir
        }
        $random = Get-Random
        $dbname1 = "dbatoolsci_restorehistory1_$random"
        $dbname2 = "dbatoolsci_restorehistory2_$random"
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1, $dbname2 | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname1 -DestinationFilePrefix $dbname1
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix $dbname2
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix "rsh_pre_$dbname2" -WithReplace
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname1, $dbname2 | Remove-DbaDatabase -Confirm:$false
    }
    Context "Preparation" {
        It "Should have prepared" {
            1 | Should -Be 1
        }
    }
    Context "Get last restore history for single database" {
        $results = @(Get-DbaRestoreHistory -SqlInstance $script:instance2 -Database $dbname2 -Last)
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
        $results = @(Get-DbaRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2 -Last)
        It "Results holds 2 objects" {
            $results.count | Should -Be 2
        }
        It "Should return the full restore with the correct properties" {
            $results[0].RestoreType | Should -Be "Database"
            $results[1].RestoreType | Should -Be "Database"
            $results[0].From | Should -Be $script:appveyorlabrepo\singlerestore\singlerestore.bak
            $results[1].From | Should -Be $script:appveyorlabrepo\singlerestore\singlerestore.bak
            ($results | Where-Object Database -eq $dbname1).To | Should -Match "\\$dbname1"
            ($results | Where-Object Database -eq $dbname2).To | Should -Match "\\rsh_pre_$dbname2"
        }
    }
    Context "Get complete restore history for multiple database" {
        $results = @(Get-DbaRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2)
        It "Results holds 3 objects" {
            $results.Count | Should -Be 3
        }
        It "Should return the full restore with the correct properties" {
            @($results | Where-Object Database -eq $dbname1).Count | Should -Be 1
            @($results | Where-Object Database -eq $dbname2).Count | Should -Be 2
        }
    }
    Context "return object properties" {
        It "has the correct properties" {
            $results = Get-DbaRestoreHistory -SqlInstance $script:instance2 -Database $dbname1, $dbname2
            $result = $results[0]
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,Username,RestoreType,Date,From,To,first_lsn,last_lsn,checkpoint_lsn,database_backup_lsn,backup_finish_date,RowError,RowState,Table,ItemArray,HasErrors'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            $ExpectedPropsDefault = 'ComputerName,InstanceName,SqlInstance,Database,Username,RestoreType,Date,From,To,backup_finish_date'.Split(',')
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}