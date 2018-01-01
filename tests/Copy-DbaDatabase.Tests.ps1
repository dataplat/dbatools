$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $NetworkPath = "C:\temp"
        $backuprestoredb = "dbatoolsci_backuprestore"
        $detachattachdb = "dbatoolsci_detachattach"
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        Stop-DbaProcess -SqlInstance $script:instance1 -Database model
        $server.Query("CREATE DATABASE $backuprestoredb")
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $backuprestoredb
        if ($db.AutoClose) {
            $db.AutoClose = $false
            $db.Alter()
        }
        Stop-DbaProcess -SqlInstance $script:instance1 -Database model
        $server.Query("CREATE DATABASE $detachattachdb")
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $Instances -Database $backuprestoredb, $detachattachdb
    }

    Context "Detach Attach" {
        It "Should be success" {
            $results = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $detachattachdb -DetachAttach -Reattach -Force -WarningAction SilentlyContinue
            $results.Status | Should Be "Successful"
        }

        It "should not be null" {
            $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $detachattachdb
            $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database $detachattachdb
            $db1 | Should Not Be $null
            $db2 | Should Not Be $null

            $db1.Name | Should Be $detachattachdb
            $db2.Name | Should Be $detachattachdb
        }

        It "Name, recovery model, and status should match" {
            # This is crazy
            (Connect-DbaInstance -SqlInstance localhost).Databases[$detachattachdb].Name | Should Be (Connect-DbaInstance -SqlInstance localhost\sql2016).Databases[$detachattachdb].Name
            (Connect-DbaInstance -SqlInstance localhost).Databases[$detachattachdb].Tables.Count | Should Be (Connect-DbaInstance -SqlInstance localhost\sql2016).Databases[$detachattachdb].Tables.Count
            (Connect-DbaInstance -SqlInstance localhost).Databases[$detachattachdb].Status | Should Be (Connect-DbaInstance -SqlInstance localhost\sql2016).Databases[$detachattachdb].Status
        }

        It "Should say skipped" {
            $results = Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $detachattachdb -DetachAttach -Reattach
            $results.Status | Should be "Skipped"
            $results.Notes | Should be "Already exists"
        }
    }

    if (-not $env:appveyor) {
        Context "Backup restore" {
            It "copies a database and retain its name, recovery model, and status." {

                Set-DbaDatabaseOwner -SqlInstance $script:instance1 -Database $backuprestoredb -TargetLogin sa
                Copy-DbaDatabase -Source $script:instance1 -Destination $script:instance2 -Database $backuprestoredb -BackupRestore -NetworkShare $NetworkPath

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
        }
    }
}