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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have Snapshot as a parameter" {
            $CommandUnderTest | Should -HaveParameter Snapshot -Type Object[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
    }
}

Describe "Restore-DbaDbSnapshot Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $script:instance2 = $script:instance2

        Get-DbaProcess -SqlInstance $script:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_RestoreSnap1"
        $db1_snap1 = "dbatoolsci_RestoreSnap1_snapshotted1"
        $db1_snap2 = "dbatoolsci_RestoreSnap1_snapshotted2"
        $db2 = "dbatoolsci_RestoreSnap2"
        $db2_snap1 = "dbatoolsci_RestoreSnap2_snapshotted1"
        Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        $server.Query("ALTER DATABASE $db1 MODIFY FILE ( NAME = N'$($db1)_log', SIZE = 13312KB )")
        $server.Query("CREATE DATABASE $db2")
        $server.Query("CREATE TABLE [$db1].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample')")
        $server.Query("CREATE TABLE [$db2].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db2].[dbo].[Example] values ('sample')")
    }

    AfterAll {
        Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }

    Context "Parameters validation" {
        It "Stops if no Database or Snapshot" {
            { Restore-DbaDbSnapshot -SqlInstance $script:instance2 -EnableException } | Should -Throw "You must specify"
        }

        It "Is nice by default" {
            { Restore-DbaDbSnapshot -SqlInstance $script:instance2 *> $null } | Should -Not -Throw
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

        It "Honors the Database parameter, restoring only snapshots of that database" {
            $result = Restore-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Confirm:$false -EnableException -Force
            $result.Status | Should -Be "Normal"
            $result.Name | Should -Be $db2

            $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample2')")
            $result = Restore-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Confirm:$false -Force
            $result.Name | Should -Be $db1

            # the other snapshot has been dropped
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1
            $result.Count | Should -Be 1

            # the query doesn't return records inserted before the restore
            $result = Invoke-DbaQuery -SqlInstance $script:instance2 -Query "SELECT * FROM [$db1].[dbo].[Example]" -QueryTimeout 10
            $result.id | Should -Be 1
        }

        It "Honors the Snapshot parameter" {
            $result = Restore-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1 -Confirm:$false -EnableException -Force
            $result.Name | Should -Be $db1
            $result.Status | Should -Be "Normal"

            # the other snapshot has been dropped
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1
            $result.SnapshotOf | Should -Be $db1
            $result.Database.Name | Should -Be $db1_snap1

            # the log size has been restored to the correct size
            $server.databases[$db1].Logfiles.Size | Should -Be 13312
        }

        It "Stops if multiple snapshot for the same db are passed" {
            $result = Restore-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1, $db1_snap2 -Confirm:$false *> $null
            $result | Should -Be $null
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}
