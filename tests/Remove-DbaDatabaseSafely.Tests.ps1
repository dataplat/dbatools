$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Destination', 'DestinationSqlCredential', 'NoDbccCheckDb', 'BackupFolder', 'CategoryName', 'JobOwner', 'AllDatabases', 'BackupCompression', 'ReuseSourceFolderStructure', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        try {
            $null = Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $db1 = "dbatoolsci_safely"
            $db2 = "dbatoolsci_safely_otherInstance"
            $server3 = Connect-DbaInstance -SqlInstance $script:instance3
            $server3.Query("CREATE DATABASE $db1")
            $server2 = Connect-DbaInstance -SqlInstance $script:instance2
            $server2.Query("CREATE DATABASE $db1")
            $server2.Query("CREATE DATABASE $db2")
            $server1 = Connect-DbaInstance -SqlInstance $script:instance1
        } catch { }
    }
    AfterAll {
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2
        $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance3 -Database $db1
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $script:instance2 -Job 'Rationalised Database Restore Script for dbatoolsci_safely'
        $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $script:instance3 -Job 'Rationalised Database Restore Script for dbatoolsci_safely_otherInstance'
    }
    Context "Command actually works" {
        It "Should have database name of $db1" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance2 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb
            foreach ($result in $results) {
                $result.DatabaseName | Should Be $db1
            }
        }

        It -Skip:$($server1.EngineEdition -notmatch "Express") "should warn and quit on Express Edition" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance1 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb -WarningAction SilentlyContinue -WarningVariable warn 3> $null
            $results | Should Be $null
            $warn -match 'Express Edition' | Should Be $true
        }

        It "Should restore to another server" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance2 -Database $db2 -BackupFolder c:\temp -NoDbccCheckDb -Destination $script:instance3
            foreach ($result in $results) {
                $result.SqlInstance | Should Be $server2.SqlInstance
                $result.TestingInstance | Should Be $server3.SqlInstance
            }
        }
    }
}