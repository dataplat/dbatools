$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Snapshot', 'ExcludeSnapshot', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "Operations on snapshots" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_GetSnap"
            $db1_snap1 = "dbatoolsci_GetSnap_snapshotted1"
            $db1_snap2 = "dbatoolsci_GetSnap_snapshotted2"
            $db2 = "dbatoolsci_GetSnap2"
            $db2_snap1 = "dbatoolsci_GetSnap2_snapshotted"
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $null = New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap1 -WarningAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap2 -WarningAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Name $db2_snap1 -WarningAction SilentlyContinue
        }
        AfterAll {
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue -Confirm:$false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        It "Gets all snapshots by default" {
            $results = Get-DbaDbSnapshot -SqlInstance $script:instance2
            ($results | Where-Object Name -Like 'dbatoolsci_GetSnap*').Count | Should Be 3
        }
        It "Honors the Database parameter, returning only snapshots of that database" {
            $results = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1
            $results.Count | Should Be 2
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2
            $result.SnapshotOf | Should Be $db2
        }
        It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
            $alldbs = (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
            $results = Get-DbaDbSnapshot -SqlInstance $script:instance2 -ExcludeDatabase $alldbs
            $results.Count | Should Be 3
        }
        It "Honors the Snapshot parameter" {
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
            $result.Name | Should Be $db1_snap1
            $result.SnapshotOf | Should Be $db1
        }
        It "Honors the ExcludeSnapshot parameter" {
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -ExcludeSnapshot $db1_snap1 -Database $db1
            $result.Name | Should Be $db1_snap2
        }
        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}