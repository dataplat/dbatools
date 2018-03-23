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
        $server.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
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
            
            It "should not be null"  {
                $db1 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $detachattachdb
                $db2 = Get-DbaDatabase -SqlInstance $script:instance3 -Database $detachattachdb
                $db1.Name | Should Be $detachattachdb
                $db2.Name | Should Be $detachattachdb
            }
            
            It "Name, recovery model, and status should match" {
                # Compare its valuable.
                $db1.Name | Should Be $db2.Name
                $db1.RecoveryModel | Should Be $db2.RecoveryModel
                $db1.Status | Should be $db2.Status
                $db1.Owner | Should be $db2.Owner
            }
            
            It "Should say skipped" {
                $results = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $detachattachdb -DetachAttach -Reattach
                $results.Status | Should be "Skipped"
                $results.Notes | Should be "Already exists"
            }
        }
    }
    
    Context "Backup restore" {
        It "copies a database and retain its name, recovery model, and status." {
            
            $null = Set-DbaDatabaseOwner -SqlInstance $script:instance2 -Database $backuprestoredb -TargetLogin sa
            Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $null = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath
            $null = Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $db1 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $backuprestoredb
            $db2 = Get-DbaDatabase -SqlInstance $script:instance3 -Database $backuprestoredb
            
            # Compare its variables
            $db1.Name | Should Be $db2.Name
            $db1.RecoveryModel | Should Be $db2.RecoveryModel
            $db1.Status | Should be $db2.Status
            $db1.Owner | Should be $db2.Owner
        }
        
        It "Should say skipped" {
            $result = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath
            $result.Status | Should be "Skipped"
            $result.Notes | Should be "Already exists"
        }
        It "Should overwrite when forced to" {
            #regr test for #3358
            $result = Copy-DbaDatabase -Source $script:instance2 -Destination $script:instance3 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath -Force
            $result.Status | Should be "Successful"
        }
    }
}