$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'Destination', 'DetachAttach', 'Reattach', 'BackupRestore', 'SharedPath', 'WithReplace', 'NoRecovery', 'AzureCredential', 'SetSourceReadOnly', 'ReuseSourceFolderStructure', 'IncludeSupportDbs', 'SourceSqlCredential', 'DestinationSqlCredential', 'Exclude', 'DisableJobsOnDestination', 'DisableJobsOnSource', 'ExcludeSaRename', 'UseLastBackup', 'Continue', 'Force', 'EnableException', 'KeepCDC', 'KeepReplication', 'MasterKeyPassword'

        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

$PSDefaultParameterValues = @{ }
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $startmigrationrestoredb = "dbatoolsci_startmigrationrestore$random"
        $startmigrationrestoredb2 = "dbatoolsci_startmigrationrestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb, $detachattachdb

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $startmigrationrestoredb; ALTER DATABASE $startmigrationrestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        $null = Set-DbaDbOwner -SqlInstance $TestConfig.instance2 -Database $startmigrationrestoredb, $detachattachdb -TargetLogin sa

        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2
        Remove-Item -Path $backupPath -Recurse
    }

    Context "Backup restore" {
        $results = Start-DbaMigration -Force -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -BackupRestore -SharedPath $backupPath -Exclude Logins, SpConfigure, SysDbUserObjects, AgentServer, CentralManagementServer, ExtendedEvents, PolicyManagement, ResourceGovernor, Endpoints, ServerAuditSpecifications, Audits, LinkedServers, SystemTriggers, DataCollector, DatabaseMail, BackupDevices, Credentials

        It "returns at least one result" {
            $results | Should -Not -Be $null
        }

        foreach ($result in $results) {
            It "copies a database successfully" {
                $result.Type -eq "Database"
                $result.Status -eq "Successful"
            }
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb2
            $dbs[0].Name -ne $null
            # Compare its variables
            $dbs[0].Name -eq $dbs[1].Name
            $dbs[0].RecoveryModel -eq $dbs[1].RecoveryModel
            $dbs[0].Status -eq $dbs[1].Status
            $dbs[0].Owner -eq $dbs[1].Owner
        }
    }

    Context "Backup restore" {
        $quickbackup = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Backup-DbaDatabase -BackupDirectory $backupPath
        $results = Start-DbaMigration -Force -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -UseLastBackup -Exclude Logins, SpConfigure, SysDbUserObjects, AgentServer, CentralManagementServer, ExtendedEvents, PolicyManagement, ResourceGovernor, Endpoints, ServerAuditSpecifications, Audits, LinkedServers, SystemTriggers, DataCollector, DatabaseMail, BackupDevices, Credentials, StartupProcedures

        It "returns at least one result" {
            $results | Should -Not -Be $null
        }

        foreach ($result in $results) {
            It "copies a database successfully" {
                $result.Type -eq "Database"
                $result.Status -eq "Successful"
            }
        }

        It "retains its name, recovery model, and status." {
            $dbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb2
            $dbs[0].Name -ne $null
            # Compare its variables
            $dbs[0].Name -eq $dbs[1].Name
            $dbs[0].RecoveryModel -eq $dbs[1].RecoveryModel
            $dbs[0].Status -eq $dbs[1].Status
            $dbs[0].Owner -eq $dbs[1].Owner
        }
    }
}
