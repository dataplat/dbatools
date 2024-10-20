param($ModuleName = 'dbatools')

Describe "New-DbaDbSnapshot" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbSnapshot
        }

        It "has the required parameter: <_>" -ForEach @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "AllDatabases",
            "Name",
            "NameSuffix",
            "Path",
            "Force",
            "InputObject",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            Get-DbaProcess -SqlInstance $global:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $db1 = "dbatoolsci_SnapMe"
            $db2 = "dbatoolsci_SnapMe2"
            $db3 = "dbatoolsci_SnapMe3_Offline"
            $db4 = "dbatoolsci_SnapMe4.WithDot"
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $server.Query("CREATE DATABASE $db3")
            $server.Query("CREATE DATABASE [$db4]")
        }

        AfterAll {
            Remove-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1, $db2, $db3, $db4 -Confirm:$false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1, $db2, $db3, $db4
        }

        It "Stops if no Database or AllDatabases" {
            { New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -WarningAction SilentlyContinue } | Should -Throw "You must specify"
        }

        It "Is nice by default" {
            { New-DbaDbSnapshot -SqlInstance $global:instance2 *> $null -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "Doesn't support model, master or tempdb" {
            $result = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database model, master, tempdb -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Skips over offline databases nicely" {
            $server.Query("ALTER DATABASE $db3 SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $result = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db3
            $result | Should -BeNullOrEmpty
            $server.Query("ALTER DATABASE $db3 SET ONLINE WITH ROLLBACK IMMEDIATE")
        }

        It "Refuses to accept multiple source databases with a single name target" {
            { New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db1, $db2 -Name "dbatools_Snapped" -WarningAction SilentlyContinue } | Should -Throw
        }

        It "Halts when path is not accessible" {
            { New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1 -Path B:\Funnydbatoolspath -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }

        It "Creates snaps for multiple dbs by default" {
            $results = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db1, $db2
            $results | Should -Not -BeNullOrEmpty
            foreach ($result in $results) {
                $result.SnapshotOf | Should -BeIn @($db1, $db2)
            }
        }

        It "Creates snap with the correct name" {
            $result = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db1 -Name "dbatools_SnapMe_right"
            $result | Should -Not -BeNullOrEmpty
            $result.SnapshotOf | Should -Be $db1
            $result.Name | Should -Be "dbatools_SnapMe_right"
        }

        It "Creates snap with the correct name template" {
            $result = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db2 -NameSuffix "dbatools_SnapMe_{0}_funny"
            $result | Should -Not -BeNullOrEmpty
            $result.SnapshotOf | Should -Be $db2
            $result.Name | Should -Be ("dbatools_SnapMe_{0}_funny" -f $db2)
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2 | Select-Object -First 1
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }

        It "Creates multiple snaps for db with dot in the name (see #8829)" {
            $results = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db4
            $results | Should -Not -BeNullOrEmpty
            foreach ($result in $results) {
                $result.SnapshotOf | Should -Be $db4
            }
            Start-Sleep -Seconds 2
            $results = New-DbaDbSnapshot -SqlInstance $global:instance2 -EnableException -Database $db4
            $results | Should -Not -BeNullOrEmpty
            foreach ($result in $results) {
                $result.SnapshotOf | Should -Be $db4
            }
        }
    }
}
