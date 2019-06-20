$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Destination', 'DestinationCredential', 'NoDbccCheckDb', 'BackupFolder', 'CategoryName', 'JobOwner', 'AllDatabases', 'BackupCompression', 'ReuseSourceFolderStructure', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $db1 = "dbatoolsci_safely"
        $db2 = "dbatoolsci_safely_otherInstance"
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $server.Query("CREATE DATABASE $db1")
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE $db1")
        $server.Query("CREATE DATABASE $db2")
    }
    AfterAll {
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance3 -Database $db1
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $script:instance2 -Job 'Rationalised Database Restore Script for dbatoolsci_safely'
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $script:instance3 -Job 'Rationalised Database Restore Script for dbatoolsci_safely_otherInstance'
    }
    Context "Command actually works" {
        $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance2 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb
        It "Should have database name of $db1" {
            foreach ($result in $results) {
                $result.DatabaseName | Should Be $db1
            }
        }

        $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance1 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb -WarningAction SilentlyContinue -WarningVariable warn
        It "should warn and quit" {
            $results | Should Be $null
            $warn -match 'Express Edition' | Should Be $true
        }

        $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance2 -Database $db2 -BackupFolder c:\temp -NoDbccCheckDb -Destination $script:instance3
        It "Should restore to another server" {
            foreach ($result in $results) {
                $result.SqlInstance | Should Be $script:instance2
                $result.TestingInstance | Should Be $script:instance3
            }
        }
    }
}