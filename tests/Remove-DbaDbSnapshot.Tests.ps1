$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Snapshot', 'InputObject', 'AllSnapshots', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_RemoveSnap"
        $db1_snap1 = "dbatoolsci_RemoveSnap_snapshotted1"
        $db1_snap2 = "dbatoolsci_RemoveSnap_snapshotted2"
        $db2 = "dbatoolsci_RemoveSnap2"
        $db2_snap1 = "dbatoolsci_RemoveSnap2_snapshotted"
        Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        $server.Query("CREATE DATABASE $db2")
    }
    AfterAll {
        Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }
    Context "Parameters validation" {
        It "Stops if no Database or AllDatabases" {
            { Remove-DbaDbSnapshot -SqlInstance $script:instance2 -EnableException -WarningAction SilentlyContinue } | Should Throw "You must pipe"
        }
        It "Is nice by default" {
            { Remove-DbaDbSnapshot -SqlInstance $script:instance2 *> $null } | Should Not Throw "You must pipe"
        }
    }

    Context "Operations on snapshots" {
        BeforeEach {
            $null = New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap1 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap2 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Name $db2_snap1 -ErrorAction SilentlyContinue
        }
        AfterEach {
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Honors the Database parameter, dropping only snapshots of that database" {
            $results = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Confirm:$false
            $results.Count | Should Be 2
            $result = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Confirm:$false
            $result.Name | Should Be $db2_snap1
        }

        It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
            $alldbs = (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
            $results = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -ExcludeDatabase $alldbs -Confirm:$false
            $results.Count | Should Be 3
        }
        It "Honors the Snapshot parameter" {
            $result = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
            $result.Name | Should Be $db1_snap1
        }
        It "Works with piped snapshots" {
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1 | Remove-DbaDbSnapshot -Confirm:$false
            $result.Name | Should Be $db1_snap1
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
            $result | Should Be $null
        }
        It "Has the correct default properties" {
            $result = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Confirm:$false
            $ExpectedPropsDefault = 'ComputerName', 'Name', 'InstanceName', 'SqlInstance', 'Status'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}