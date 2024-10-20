$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Primary', 'PrimarySqlCredential', 'Secondary', 'SecondarySqlCredential', 'Name', 'ReuseSystemDatabases', 'IsContained', 'DtcSupport', 'ClusterType', 'AutomatedBackupPreference', 'FailureConditionLevel', 'HealthCheckTimeout', 'Basic', 'DatabaseHealthTrigger', 'Passthru', 'Database', 'SharedPath', 'UseLastBackup', 'Force', 'AvailabilityMode', 'FailoverMode', 'BackupPriority', 'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'SeedingMode', 'Endpoint', 'EndpointUrl', 'Certificate', 'ConfigureXESession', 'IPAddress', 'SubnetMask', 'Port', 'Dhcp', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_addag_agroupdb"
        $agname = "dbatoolsci_addag_agroup"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbname | Backup-DbaDatabase
    }
    AfterEach {
        $result = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbname -Confirm:$false
    }
    Context "adds an ag" {
        It "returns an ag with a db named" {
            $results = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Name | Should -Be $dbname
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }
        It "returns an ag with no database if one was not named" {
            $results = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }
} #$TestConfig.instance2 for appveyor
