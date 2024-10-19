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
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have DetachAttach as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DetachAttach
        }
        It "Should have Reattach as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Reattach
        }
        It "Should have BackupRestore as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter BackupRestore
        }
        It "Should have SharedPath as a string parameter" {
            $CommandUnderTest | Should -HaveParameter SharedPath
        }
        It "Should have WithReplace as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter WithReplace
        }
        It "Should have NoRecovery as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery
        }
        It "Should have SetSourceReadOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SetSourceReadOnly
        }
        It "Should have ReuseSourceFolderStructure as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReuseSourceFolderStructure
        }
        It "Should have IncludeSupportDbs as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSupportDbs
        }
        It "Should have SourceSqlCredential as a PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have DestinationSqlCredential as a PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Exclude as a string array parameter" {
            $CommandUnderTest | Should -HaveParameter Exclude
        }
        It "Should have DisableJobsOnDestination as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableJobsOnDestination
        }
        It "Should have DisableJobsOnSource as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableJobsOnSource
        }
        It "Should have ExcludeSaRename as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSaRename
        }
        It "Should have UseLastBackup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseLastBackup
        }
        It "Should have KeepCDC as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepCDC
        }
        It "Should have KeepReplication as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepReplication
        }
        It "Should have Continue as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Continue
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have AzureCredential as a string parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential
        }
        It "Should have MasterKeyPassword as a SecureString parameter" {
            $CommandUnderTest | Should -HaveParameter MasterKeyPassword
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
