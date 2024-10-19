param($ModuleName = 'dbatools')

Describe "Start-DbaMigration" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $startmigrationrestoredb = "dbatoolsci_startmigrationrestore$random"
        $startmigrationrestoredb2 = "dbatoolsci_startmigrationrestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2, $global:instance3 -Database $startmigrationrestoredb, $detachattachdb

        $server = Connect-DbaInstance -SqlInstance $global:instance3
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $startmigrationrestoredb; ALTER DATABASE $startmigrationrestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        $null = Set-DbaDbOwner -SqlInstance $global:instance2 -Database $startmigrationrestoredb, $detachattachdb -TargetLogin sa
    }

    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2, $global:instance3 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaMigration
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "Source",
                "Destination",
                "DetachAttach",
                "Reattach",
                "BackupRestore",
                "SharedPath",
                "WithReplace",
                "NoRecovery",
                "SetSourceReadOnly",
                "ReuseSourceFolderStructure",
                "IncludeSupportDbs",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Exclude",
                "DisableJobsOnDestination",
                "DisableJobsOnSource",
                "ExcludeSaRename",
                "UseLastBackup",
                "KeepCDC",
                "KeepReplication",
                "Continue",
                "Force",
                "AzureCredential",
                "MasterKeyPassword",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Backup restore" {
        BeforeAll {
            $results = Start-DbaMigration -Force -Source $global:instance2 -Destination $global:instance3 -BackupRestore -SharedPath "C:\temp" -Exclude Logins, SpConfigure, SysDbUserObjects, AgentServer, CentralManagementServer, ExtendedEvents, PolicyManagement, ResourceGovernor, Endpoints, ServerAuditSpecifications, Audits, LinkedServers, SystemTriggers, DataCollector, DatabaseMail, BackupDevices, Credentials
        }

        It "returns at least one result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "copies databases successfully" {
            $results | Where-Object { $_.Type -eq "Database" } | ForEach-Object {
                $_.Status | Should -Be "Successful"
            }
        }

        It "retains its name, recovery model, and status" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $startmigrationrestoredb2
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
            $dbs[0].Owner | Should -Be $dbs[1].Owner
        }
    }

    Context "Backup restore using last backup" {
        BeforeAll {
            $quickbackup = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeSystem | Backup-DbaDatabase -BackupDirectory C:\temp
            $results = Start-DbaMigration -Force -Source $global:instance2 -Destination $global:instance3 -UseLastBackup -Exclude Logins, SpConfigure, SysDbUserObjects, AgentServer, CentralManagementServer, ExtendedEvents, PolicyManagement, ResourceGovernor, Endpoints, ServerAuditSpecifications, Audits, LinkedServers, SystemTriggers, DataCollector, DatabaseMail, BackupDevices, Credentials, StartupProcedures
        }

        It "returns at least one result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "copies databases successfully" {
            $results | Where-Object { $_.Type -eq "Database" } | ForEach-Object {
                $_.Status | Should -Be "Successful"
            }
        }

        It "retains its name, recovery model, and status" {
            $dbs = Get-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Database $startmigrationrestoredb2
            $dbs[0].Name | Should -Not -BeNullOrEmpty
            $dbs[0].Name | Should -Be $dbs[1].Name
            $dbs[0].RecoveryModel | Should -Be $dbs[1].RecoveryModel
            $dbs[0].Status | Should -Be $dbs[1].Status
            $dbs[0].Owner | Should -Be $dbs[1].Owner
        }
    }
}
