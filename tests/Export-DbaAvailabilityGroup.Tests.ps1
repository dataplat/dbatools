$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    $dbname = "dbatoolsci_agroupdb"
    if (-not $env:appveyor) {
        BeforeAll {
            # $script:instance2 - to make it appear in the proper place on appveyor
            Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $computername = $server.NetName
            $servicename = $server.ServiceName
            if ($servicename -eq 'MSSQLSERVER') {
                $instancename = "$computername"
            }
            else {
                $instancename = "$computername\$servicename"
            }
            $server.Query("create database $dbname")
            $backup = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase
            $server.Query("IF NOT EXISTS (select * from sys.symmetric_keys where name like '%DatabaseMasterKey%') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'")
            $server.Query("IF EXISTS ( SELECT * FROM sys.tcp_endpoints WHERE name = 'End_Mirroring') DROP ENDPOINT endpoint_mirroring")
            $server.Query("CREATE CERTIFICATE dbatoolsci_AGCert WITH SUBJECT = 'AG Certificate'")
            $server.Query("CREATE ENDPOINT dbatoolsci_AGEndpoint
                            STATE = STARTED
                            AS TCP (LISTENER_PORT = 5022,LISTENER_IP = ALL)
                            FOR DATABASE_MIRRORING (AUTHENTICATION = CERTIFICATE dbatoolsci_AGCert,ROLE = ALL)")
            $server.Query("CREATE AVAILABILITY GROUP dbatoolsci_agroup
                            WITH (DB_FAILOVER = OFF, DTC_SUPPORT = NONE, CLUSTER_TYPE = NONE)
                            FOR DATABASE $dbname REPLICA ON N'$instancename'
                            WITH (ENDPOINT_URL = N'TCP://$computername`:5022', FAILOVER_MODE = MANUAL, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT)")
        }
        AfterAll {
            try {
                if ($backup.BackupPath) { Remove-Item -Path $backup.BackupPath -ErrorAction SilentlyContinue }
                $server.Query("DROP AVAILABILITY GROUP dbatoolsci_agroup")
                Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
                $server.Query("DROP ENDPOINT dbatoolsci_AGEndpoint")
                $server.Query("DROP CERTIFICATE dbatoolsci_AGCert")
            }
            catch {
                # dont care
            }
        }
    }
    Context "exports ags" {
        $results = Export-DbaAvailabilityGroup -SqlInstance $script:instance3
        It "returns file objects and one should be the name of the availability group" {
            $results.BaseName | Should -Contain 'dbatoolsci_agroup'
        }
        It "the files it returns should contain the term 'CREATE AVAILABILITY GROUP'" {
            $results | Select-String 'CREATE AVAILABILITY GROUP' | Should -Not -Be $null
        }
        $results | Remove-Item -ErrorAction SilentlyContinue
        $results = Export-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup dbatoolsci_agroup -FilePath C:\temp
        It "returns a single result" {
            $results.BaseName | Should -Be 'dbatoolsci_agroup'
        }
        It "the file it returns should contain the term 'CREATE AVAILABILITY GROUP'" {
            $results | Select-String 'CREATE AVAILABILITY GROUP' | Should -Not -Be $null
        }
        It "the file's path should match C:\temp" {
            $results.FullName -match 'C:\\temp' | Should -Be $true
        }
        $results | Remove-Item -ErrorAction SilentlyContinue
    }
}
# $script:instance2 - to make it appear in the proper place on appveyor