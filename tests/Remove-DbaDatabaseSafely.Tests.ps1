$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Destination', 'DestinationCredential', 'NoDbccCheckDb', 'BackupFolder', 'CategoryName', 'JobOwner', 'AllDatabases', 'BackupCompression', 'ReuseSourceFolderStructure', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        try {
            $null = Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $db1 = "dbatoolsci_safely"
            $db2 = "dbatoolsci_safely_otherInstance"
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $server.Query("CREATE DATABASE $db1")
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
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

        It "should warn and quit" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance1 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should Be $null
            $warn -match 'Express Edition' | Should Be $true
        }

        It "Should restore to another server" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $script:instance2 -Database $db2 -BackupFolder c:\temp -NoDbccCheckDb -Destination $script:instance3
            foreach ($result in $results) {
                $result.SqlInstance | Should Be $script:instance2
                $result.TestingInstance | Should Be $script:instance3
            }
        }
    }
}