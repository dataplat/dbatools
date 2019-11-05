$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Primary', 'PrimarySqlCredential', 'Secondary', 'SecondarySqlCredential', 'Name', 'DtcSupport', 'ClusterType', 'AutomatedBackupPreference', 'FailureConditionLevel', 'HealthCheckTimeout', 'Basic', 'DatabaseHealthTrigger', 'Passthru', 'Database', 'SharedPath', 'UseLastBackup', 'Force', 'AvailabilityMode', 'FailoverMode', 'BackupPriority', 'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'SeedingMode', 'Endpoint', 'ReadonlyRoutingConnectionUrl', 'Certificate', 'IPAddress', 'SubnetMask', 'Port', 'Dhcp', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $computername = ($script:instance3).Split("\")[0]
        $null = Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $dbname = "dbatoolsci_addag_agroupdb"
        $server.Query("create database $dbname")
        $agname = "dbatoolsci_addag_agroup"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $null = New-DbaDbMasterKey -SqlInstance $script:instance3 -Database master -WarningAction SilentlyContinue -ErrorAction Ignore -EnableException:$false -SecurePassword $securePassword -Confirm:$false
        $null = New-DbaDbCertificate -SqlInstance $script:instance3 -Database master -Name dbatoolsci_AGCert -Subject 'AG Certificate' -ErrorAction Ignore
        $null = New-DbaEndpoint -SqlInstance $script:instance3 -Type DatabaseMirroring -Name dbatoolsci_AGEndpoint -Certificate dbatoolsci_AGCert | Start-DbaEndpoint
        $backup = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
        $null = Remove-DbaEndpoint -SqlInstance $server -Endpoint dbatoolsci_AGEndpoint -Confirm:$false
        $null = Get-DbaDbCertificate -SqlInstance $server -Certificate dbatoolsci_AGCert | Remove-DbaDbCertificate -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
    }
    Context "adds an ag" {
        It "returns an ag with a db named" {
            $results = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Name | Should -Be $dbname
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }
        It "returns an ag with no database if one was not named" {
            $results = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }
} #$script:instance2 for appveyor