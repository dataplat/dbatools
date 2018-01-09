$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
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
        $db1 = "dbatoolsci_RestoreSnap1"
        $db1_snap1 = "dbatoolsci_RestoreSnap1_snapshotted1"
        $db1_snap2 = "dbatoolsci_RestoreSnap1_snapshotted2"
        $db2 = "dbatoolsci_RestoreSnap2"
        $db2_snap1 = "dbatoolsci_RestoreSnap2_snapshotted1"
        Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Force
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        $server.Query("ALTER DATABASE $db1 MODIFY FILE ( NAME = N'$($db1)_log', SIZE = 13312KB )")
        $server.Query("CREATE DATABASE $db2")
        $server.Query("CREATE TABLE [$db1].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample')")
        $server.Query("CREATE TABLE [$db2].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db2].[dbo].[Example] values ('sample')")
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
        It "Stops if no Database or Snapshot" {
            { Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 -EnableException } | Should Throw "You must specify"
        }
        It "Is nice by default" {
            { Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 *> $null } | Should Not Throw "You must specify"
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
            It "Honors the Database parameter, restoring only snapshots of that database" {
                $result = Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
                $result.Status | Should Be "Restored"
                $result.Snapshot | Should Be $db2_snap1
                $result.Database | Should Be $db2

                $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample2')")

                $result = Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Force
                $result.Status | Should Be "Restored"
                $result.Snapshot | Should Be $db1_snap2
                $result.Database | Should Be $db1
                # the other snapshot has been dropped
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1
                $result.SnapshotOf | Should Be $db1
                $result.Database | Should Be $db1_snap2
                # the query doesn't retrn records inserted before the restore
                $result = Invoke-SqlCmd2 -ServerInstance $script:instance2 -Query "SELECT * FROM [$db1].[dbo].[Example]" -QueryTimeout 1 -ConnectionTimeout 1
                $result.id | Should Be 1
            }
            It "Honors the Snapshot parameter" {
                $result = Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1 -Force
                $result.Database | Should Be $db1
                $result.Status | Should Be "Restored"
                $result.Snapshot | Should Be $db1_snap1
                # the other snapshot has been dropped
                $result = Get-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1
                $result.SnapshotOf | Should Be $db1
                $result.Database.Name | Should Be $db1_snap
                # the log size has been restored to the correct size
                $server.databases[$db1].Logfiles.Size | Should Be 13312

            }
            It "Stops if multiple snapshot for the same db are passed" {
                $result = Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1, $db1_snap2 -Force *> $null
                $result | Should Be $null
            }
            It "Has the correct properties" {
                $result = Restore-DbaFromDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
                $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,Snapshot,Status,Notes'.Split(',')
                ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }
        }
    }
}


