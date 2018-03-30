$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAvailabilityGroup).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'IsPrimary', 'EnableException'
        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

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
            $dbname = "dbatoolsci_agroupdb"
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
    Context "gets ags" {
        $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3
        It "returns results with proper data" {
            $results.AvailabilityGroup | Should -Contain 'dbatoolsci_agroup'
            $results.AvailabilityDatabases.Name | Should -Contain $dbname
        }
        $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup dbatoolsci_agroup
        It "returns a single result" {
            $results.AvailabilityGroup | Should -Be 'dbatoolsci_agroup'
            $results.AvailabilityDatabases.Name | Should -Be $dbname
        }
    }
}