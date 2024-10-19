param($ModuleName = 'dbatools')

Describe "Restore-DbaDbSnapshot Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Restore-DbaDbSnapshot
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Snapshot",
                "InputObject"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
            $CommandUnderTest | Should -HaveParameter Force
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Restore-DbaDbSnapshot Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"

        Get-DbaProcess -SqlInstance $global:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $db1 = "dbatoolsci_RestoreSnap1"
        $db1_snap1 = "dbatoolsci_RestoreSnap1_snapshotted1"
        $db1_snap2 = "dbatoolsci_RestoreSnap1_snapshotted2"
        $db2 = "dbatoolsci_RestoreSnap2"
        $db2_snap1 = "dbatoolsci_RestoreSnap2_snapshotted1"
        Remove-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1, $db2 -Confirm:$false
        Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        $server.Query("ALTER DATABASE $db1 MODIFY FILE ( NAME = N'$($db1)_log', SIZE = 13312KB )")
        $server.Query("CREATE DATABASE $db2")
        $server.Query("CREATE TABLE [$db1].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample')")
        $server.Query("CREATE TABLE [$db2].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db2].[dbo].[Example] values ('sample')")
    }

    AfterAll {
        Remove-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }

    Context "Parameters validation" {
        It "Stops if no Database or Snapshot" {
            { Restore-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException } | Should -Throw "You must specify"
        }

        It "Is nice by default" {
            { Restore-DbaDbSnapshot -SqlInstance $global:instance2 *> $null } | Should -Not -Throw
        }
    }

    Context "Operations on snapshots" {
        BeforeEach {
            $null = New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1 -Name $db1_snap1 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1 -Name $db1_snap2 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2 -Name $db2_snap1 -ErrorAction SilentlyContinue
        }

        AfterEach {
            Remove-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Honors the Database parameter, restoring only snapshots of that database" {
            $result = Restore-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2 -Confirm:$false -EnableException -Force
            $result.Status | Should -Be "Normal"
            $result.Name | Should -Be $db2

            $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample2')")
            $result = Restore-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1 -Confirm:$false -Force
            $result.Name | Should -Be $db1

            # the other snapshot has been dropped
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1
            $result.Count | Should -Be 1

            # the query doesn't return records inserted before the restore
            $result = Invoke-DbaQuery -SqlInstance $global:instance2 -Query "SELECT * FROM [$db1].[dbo].[Example]" -QueryTimeout 10
            $result.id | Should -Be 1
        }

        It "Honors the Snapshot parameter" {
            $result = Restore-DbaDbSnapshot -SqlInstance $global:instance2 -Snapshot $db1_snap1 -Confirm:$false -EnableException -Force
            $result.Name | Should -Be $db1
            $result.Status | Should -Be "Normal"

            # the other snapshot has been dropped
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1
            $result.SnapshotOf | Should -Be $db1
            $result.Database.Name | Should -Be $db1_snap1

            # the log size has been restored to the correct size
            $server.databases[$db1].Logfiles.Size | Should -Be 13312
        }

        It "Stops if multiple snapshot for the same db are passed" {
            $result = Restore-DbaDbSnapshot -SqlInstance $global:instance2 -Snapshot $db1_snap1, $db1_snap2 -Confirm:$false *> $null
            $result | Should -Be $null
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}
