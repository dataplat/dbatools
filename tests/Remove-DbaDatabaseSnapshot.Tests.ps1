$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_RemoveSnap"
        $db1_snap1 = "dbatoolsci_RemoveSnap_snapshotted1"
        $db1_snap2 = "dbatoolsci_RemoveSnap_snapshotted2"
        $db2 = "dbatoolsci_RemoveSnap2"
        $db2_snap1 = "dbatoolsci_RemoveSnap2_snapshotted"
        Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Force
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        $server.Query("CREATE DATABASE $db2")
        $needed = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2
        $setupright = $true
        if ($needed.Count -ne 2) {
            $setupright = $false
            it "has failed setup" {
                Set-TestInconclusive -message "Setup failed"
            }
        }
    }
    AfterAll {
        Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Force -ErrorAction SilentlyContinue
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }
    Context "Parameters validation" {
        It "Stops if no Database or AllDatabases" {
            { Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException } | Should Throw "You must specify"
        }
        It "Is nice by default" {
            { Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 *> $null } | Should Not Throw "You must specify"
        }
    }

    Context "Operations on snapshots" {
        BeforeEach {
            $needed = @()
            $needed += New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap1 -ErrorAction SilentlyContinue
            $needed += New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap2 -ErrorAction SilentlyContinue
            $needed += New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Name $db2_snap1 -ErrorAction SilentlyContinue
            if ($needed.Count -ne 3) {
                Set-TestInconclusive -message "Setup failed"
            }
        }
        AfterEach {
            Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Force -ErrorAction SilentlyContinue
        }

        if ($setupright) {
            It "Honors the Database parameter, dropping only snapshots of that database" {
                $results = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Force
                $results.Count | Should Be 2
                $result = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
                $result.SnapshotOf | Should Be $db2
            }
            It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
                $alldbs = (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
                $results = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -ExcludeDatabase $alldbs -Force
                $results.Count | Should Be 3
            }
            It "Honors the Snapshot parameter" {
                $result = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
                $result.Database.Name | Should Be $db1_snap1
                $result.SnapshotOf | Should Be $db1
            }
            It "Works with piped snapshots" {
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1 | Remove-DbaDatabaseSnapshot -Force
                $result.Database | Should Be $db1_snap1
                $result.SnapshotOf | Should Be $db1
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
                $result | Should Be $null
            }
            It "Has the correct properties" {
                $result = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
                $ExpectedProps = 'ComputerName,Database,InstanceName,SnapshotOf,SqlInstance,Status'.Split(',')
                ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }

        }
    }
}


