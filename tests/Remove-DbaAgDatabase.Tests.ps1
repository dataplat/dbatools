$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Remove-DbaAvailabilityGroup).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'AllAvailabilityGroups', 'InputObject', 'EnableException'
        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $computername = ($script:instance3).Split("\")[0]
        $null = Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $dbname = "dbatoolsci_removeag_agroupdb"
        $server.Query("create database $dbname")
        $agname = "dbatoolsci_agdb"
        $backup = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase
        # New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false
        $server.Query("CREATE AVAILABILITY GROUP dbatoolsci_agroup
                            WITH (DB_FAILOVER = OFF, DTC_SUPPORT = NONE, CLUSTER_TYPE = NONE)
                            FOR DATABASE $dbname REPLICA ON N'$script:instance3'
                            WITH (ENDPOINT_URL = N'TCP://$computername`:5022', FAILOVER_MODE = MANUAL, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT)")
    }
    AfterAll {
        Remove-DbaAgDatabase -SqlInstance $server -Database $dbname -Confirm:$false
        Get-DbaAgDatabase -SqlInstance $server -Database $dbname | Remove-DbaAgDatabase -Confirm:$false
        Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup dbatoolsci_agroup -Confirm:$false
        Remove-DbaEndpoint -SqlInstance $server -Endpoint dbatoolsci_AGEndpoint -Confirm:$false
        Get-DbaDbCertificate -SqlInstance $server -Certificate dbatoolsci_AGCert | Remove-DbaDbCertificate -Confirm:$false
        Get-DbaAgDatabase -SqlInstance $server -Database $dbname | Remove-DbaAgDatabase -Confirm:$false
        Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
    }
    Context "removes ag db" {
        It "returns removed results" {
            $results = Remove-DbaAgDatabase -SqlInstance $script:instance3 -Database $dbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be 'dbatoolsci_agroup'
            $results.Database | Should -Be $dbname
            $results.Status | Should -Be 'Removed'
        }
        
        It "really removed the db from the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup dbatoolsci_agroup
            $results.AvailabilityGroup | Should -Be 'dbatoolsci_agroup'
            $results.AvailabilityDatabases.Name | Should -Not -Contain $dbname
        }
    }
} #$script:instance2 for appveyor