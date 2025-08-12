$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'Name', 'NameSuffix', 'Path', 'Force', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Parameter validation" {
        It "Stops if no Database or AllDatabases" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -WarningAction SilentlyContinue } | Should Throw "You must specify"
        }
        It "Is nice by default" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 *> $null -WarningAction SilentlyContinue } | Should Not Throw "You must specify"
        }
    }

    Context "Operations on not supported databases" {
        It "Doesn't support model, master or tempdb" {
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database model, master, tempdb -WarningAction SilentlyContinue
            $result | Should Be $null
        }
    }

    Context "Operations on databases" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            Get-DbaProcess -SqlInstance $TestConfig.instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
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
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1, $db2, $db3, $db4 -Confirm:$false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $db1, $db2, $db3, $db4
        }

        It "Skips over offline databases nicely" {
            $server.Query("ALTER DATABASE $db3 SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db3
            $result | Should Be $null
            $server.Query("ALTER DATABASE $db3 SET ONLINE WITH ROLLBACK IMMEDIATE")
        }

        It "Refuses to accept multiple source databases with a single name target" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db1, $db2 -Name "dbatools_Snapped" -WarningAction SilentlyContinue } | Should Throw
        }

        It "Halts when path is not accessible" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1 -Path B:\Funnydbatoolspath -EnableException -WarningAction SilentlyContinue } | Should Throw
        }

        It "Creates snaps for multiple dbs by default" {
            $results = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db1, $db2
            $results | Should Not Be $null
            foreach ($result in $results) {
                $result.SnapshotOf -in @($db1, $db2) | Should Be $true
            }
        }

        It "Creates snap with the correct name" {
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db1 -Name "dbatools_SnapMe_right"
            $result | Should Not Be $null
            $result.SnapshotOf | Should Be $db1
            $result.Name | Should Be "dbatools_SnapMe_right"
        }

        It "Creates snap with the correct name template" {
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db2 -NameSuffix "dbatools_SnapMe_{0}_funny"
            $result | Should Not Be $null
            $result.SnapshotOf | Should Be $db2
            $result.Name | Should Be ("dbatools_SnapMe_{0}_funny" -f $db2)
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db2 | Select-Object -First 1
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
        }

        It "Creates multiple snaps for db with dot in the name (see #8829)" {
            $results = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db4
            $results | Should Not Be $null
            foreach ($result in $results) {
                $result.SnapshotOf -in @($db4) | Should Be $true
            }
            Start-Sleep -Seconds 2
            $results = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $db4
            $results | Should Not Be $null
            foreach ($result in $results) {
                $result.SnapshotOf -in @($db4) | Should Be $true
            }
        }
    }
}
