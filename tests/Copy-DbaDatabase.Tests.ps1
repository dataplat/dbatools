$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $NetworkPath = "C:\temp"
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb, $detachattachdb
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb, $detachattachdb
    }
    
    # appveyor doesnt support bits yet
    if (-not $env:appveyor) {
        Context "Detach Attach" {
            It "Should be success" {
                $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $detachattachdb -DetachAttach -Reattach -Force #-WarningAction SilentlyContinue
                $results.Status | Should Be "Successful"
            }
            
            $db1 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $script:instance3 -Database $detachattachdb
            
            It "should not be null"  {
                $db1.Name | Should Be $detachattachdb
                $db2.Name | Should Be $detachattachdb
            }
            
            It "Name, recovery model, and status should match" {
                # Compare its variable
                $db1.Name | Should -Be $db2.Name
                $db1.RecoveryModel | Should -Be $db2.RecoveryModel
                $db1.Status | Should -Be $db2.Status
                $db1.Owner | Should -Be $db2.Owner
            }
            
            It "Should say skipped" {
                $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $detachattachdb -DetachAttach -Reattach
                $results.Status | Should be "Skipped"
                $results.Notes | Should be "Already exists"
            }
        }
    }
    
    Context "Backup restore" {
        $null = Set-DbaDatabaseOwner -SqlInstance $script:instance2 -Database $backuprestoredb -TargetLogin sa
        Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath
        
        It "copies a database successfully" {
            $results.Name -eq $backuprestoredb
            $results.Status -eq "Successful"
        }
        
        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Database $backuprestoredb
            $dbs[0].Name -ne $null
            # Compare its variables
            $dbs[0].Name -eq $dbs[1].Name
            $dbs[0].RecoveryModel -eq $dbs[1].RecoveryModel
            $dbs[0].Status -eq $dbs[1].Status
            $dbs[0].Owner -eq $dbs[1].Owner
        }
        
        # to be removed when #3377 is solved
        $sql = "exec msdb..sp_delete_database_backuphistory @database_name = '$backuprestoredb'"
        $server.Query($sql)
        
        It "Should say skipped" {
            $result = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath
            $result.Status | Should be "Skipped"
            $result.Notes | Should be "Already exists"
        }
        
        # to be removed when #3377 is solved
        $sql = "exec msdb..sp_delete_database_backuphistory @database_name = '$backuprestoredb'"
        $server.Query($sql)
        
        It "Should overwrite when forced to" {
            #regr test for #3358
            $result = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath -Force
            $result.Status | Should be "Successful"
        }
    }
}