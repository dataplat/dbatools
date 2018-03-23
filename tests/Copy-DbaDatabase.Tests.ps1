$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $NetworkPath = "C:\temp"
        $random = Get-Random
        $backuprestoredb = "dbatoolsci_backuprestore$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1,$script:instance2 -Database $backuprestoredb, $detachattachdb
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $server.Query("CREATE DATABASE $backuprestoredb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $server.Query("CREATE DATABASE $detachattachdb; ALTER DATABASE $backuprestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1,$script:instance2 -Database $backuprestoredb, $detachattachdb
    }

    Context "Detach Attach" {
        It "Should be success"  -Skip {
            $results = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $detachattachdb -DetachAttach -Reattach -Force -WarningAction SilentlyContinue
            $results.Status | Should Be "Successful"
        }

        It "should not be null"  -Skip  {
            $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $detachattachdb
            $db1 | Should Not Be $null
            $db2 | Should Not Be $null

            $db1.Name | Should Be $detachattachdb
            $db2.Name | Should Be $detachattachdb
        }

        It "Name, recovery model, and status should match"  -Skip {
            $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $backuprestoredb
            $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $backuprestoredb
            $db1 | Should Not BeNullOrEmpty
            $db2 | Should Not BeNullOrEmpty

            # Compare its valuable.
            $db1.Name | Should Be $db2.Name
            $db1.RecoveryModel | Should Be $db2.RecoveryModel
            $db1.Status | Should be $db2.Status
            $db1.Owner | Should be $db2.Owner
        }

        It "Should say skipped"  -Skip {
            $results = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $detachattachdb -DetachAttach -Reattach
            $results.Status | Should be "Skipped"
            $results.Notes | Should be "Already exists"
        }
    }

    Context "Backup restore" {
        It "copies a database and retain its name, recovery model, and status." {

            $null = Set-DbaDatabaseOwner -SqlInstance $script:instance1 -Database $backuprestoredb -TargetLogin sa
            $null = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath

            $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $backuprestoredb
            $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $backuprestoredb
            $db1 | Should Not BeNullOrEmpty
            $db2 | Should Not BeNullOrEmpty

            # Compare its valuable.
            $db1.Name | Should Be $db2.Name
            $db1.RecoveryModel | Should Be $db2.RecoveryModel
            $db1.Status | Should be $db2.Status
            $db1.Owner | Should be $db2.Owner
        }

        It "Should say skipped" {
            $result = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath
            $result.Status | Should be "Skipped"
            $result.Notes | Should be "Already exists"
        }
        It "Should overwrite when forced to" {
            #regr test for #3358
            $result = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath -Force
            $result.Status | Should be "Successful"
        }
    }
}