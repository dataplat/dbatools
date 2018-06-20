$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Operations on snapshots" {
        BeforeAll {
            
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_GetSnap"
            $db1_snap1 = "dbatoolsci_GetSnap_snapshotted1"
            $db1_snap2 = "dbatoolsci_GetSnap_snapshotted2"
            $db2 = "dbatoolsci_GetSnap2"
            $db2_snap1 = "dbatoolsci_GetSnap2_snapshotted"
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $setupright = $true
            $needed = @()
            $needed += New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap1 -WarningAction SilentlyContinue
            $needed += New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap2 -WarningAction SilentlyContinue
            $needed += New-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Name $db2_snap1 -WarningAction SilentlyContinue
            if ($needed.Count -ne 3) {
                $setupright = $false
                it "has failed setup" {
                    Set-TestInconclusive -message "Setup failed"
                }
            }
        }
        AfterAll {
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue -Confirm:$false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        if ($setupright) {
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
                $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance'
                ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
            }
        }
    }
}