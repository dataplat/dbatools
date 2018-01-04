$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Operations on snapshots" {
        BeforeAll {
            if ($env:appveyor) {
                Get-Service | Where-Object { $_.DisplayName -match 'SQL Server (SQL2016)' } | Restart-Service -Force

                do {
                    Start-Sleep 1
                    $null = (& sqlcmd -S $script:instance2 -b -Q "select 1" -d master)
                }
                while ($lastexitcode -ne 0 -and $s++ -lt 10)
            }
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_GetSnap"
            $db1_snap1 = "dbatoolsci_GetSnap_snapshotted1"
            $db1_snap2 = "dbatoolsci_GetSnap_snapshotted2"
            $db2 = "dbatoolsci_GetSnap2"
            $db2_snap1 = "dbatoolsci_GetSnap2_snapshotted"
            Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Force
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $setupright = $true
            $needed = @()
            $needed += New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap1 -WarningAction SilentlyContinue
            $needed += New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Name $db1_snap2 -WarningAction SilentlyContinue
            $needed += New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Name $db2_snap1 -WarningAction SilentlyContinue
            if ($needed.Count -ne 3) {
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

        if ($setupright) {
            It "Gets all snapshots by default" {
                $results = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2
                ($results | Where-Object Database -Like 'dbatoolsci_GetSnap*').Count | Should Be 3
            }
            It "Honors the Database parameter, returning only snapshots of that database" {
                $results = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1
                $results.Count | Should Be 2
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2
                $result.SnapshotOf | Should Be $db2
            }
            It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
                $alldbs = (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
                $results = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -ExcludeDatabase $alldbs
                $results.Count | Should Be 3
            }
            It "Honors the Snapshot parameter" {
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
                $result.Database | Should Be $db1_snap1
                $result.SnapshotOf | Should Be $db1
            }
            It "Honors the ExcludeSnapshot parameter" {
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -ExcludeSnapshot $db1_snap1 -Database $db1
                $result.Database | Should Be $db1_snap2
            }
            It "has the correct properties" {
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2
                $ExpectedProps = 'ComputerName,Database,DatabaseCreated,InstanceName,SizeMB,SnapshotDb,SnapshotOf,SqlInstance'.Split(',')
                ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
                $ExpectedPropsDefault = 'ComputerName,Database,DatabaseCreated,InstanceName,SizeMB,SnapshotOf,SqlInstance'.Split(',')
                ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
            }
        }
    }
}


