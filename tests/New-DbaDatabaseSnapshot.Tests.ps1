$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Parameter validation" {
        It "Stops if no Database or AllDatabases" {
            { New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException } | Should Throw "You must specify"
        }
        It "Is nice by default" {
            { New-DbaDatabaseSnapshot -SqlInstance $script:instance2 *> $null } | Should Not Throw "You must specify"
        }
    }

    Context "Operations on not supported databases" {
        It "Doesn't support model, master or tempdb" {
            $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database model, master, tempdb
            $result | Should Be $null
        }

    }
    Context "Operations on databases" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_SnapMe"
            $db2 = "dbatoolsci_SnapMe2"
            $db3 = "dbatoolsci_SnapMe3_Offline"
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $server.Query("CREATE DATABASE $db3")
            $needed = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2, $db3
            $setupright = $true
            if ($needed.Count -ne 3) {
                $setupright = $false
                it "has failed setup" {
                    Set-TestInconclusive -message "Setup failed"
                }
            }
        }
        AfterAll {
            Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1, $db2, $db3 -Force
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2, $db3
        }

        if ($setupright) {
            if (-not $env:appveyor) {
                It "Skips over offline databases nicely" {
                    $server.Query("ALTER DATABASE $db3 SET OFFLINE WITH ROLLBACK IMMEDIATE")
                    $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db3
                    $result | Should Be $null
                    $server.Query("ALTER DATABASE $db3 SET ONLINE WITH ROLLBACK IMMEDIATE")
                }
            }
            It "Refuses to accept multiple source databases with a single name target" {
                { New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db1, $db2 -Name "dbatools_Snapped" } | Should Throw
            }
            It "Halts when path is not accessible" {
                { New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db1 -Path B:\Funnydbatoolspath -EnableException } | Should Throw
            }
            It "Creates snaps for multiple dbs by default" {
                $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db1, $db2
                $result | Should Not Be $null
                foreach ($r in $result) {
                    $r.SnapshotOf -in @($db1, $db2) | Should Be $true
                }
            }
            It "Creates snap with the correct name" {
                $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db1 -Name "dbatools_SnapMe_right"
                $result | Should Not Be $null
                $result.SnapshotOf | Should Be $db1
                $result.Database | Should Be "dbatools_SnapMe_right"
            }
            It "Creates snap with the correct name template" {
                $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db2 -NameSuffix "dbatools_SnapMe_{0}_funny"
                $result | Should Not Be $null
                $result.SnapshotOf | Should Be $db2
                $result.Database | Should Be ("dbatools_SnapMe_{0}_funny" -f $db2)
            }
            It "Has the correct properties" {
                $null = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
                $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db2
                $ExpectedProps = 'ComputerName,Database,DatabaseCreated,InstanceName,Notes,PrimaryFilePath,SizeMB,SnapshotDb,SnapshotOf,SqlInstance,Status'.Split(',')
                ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }
            It "Has the correct default properties" {
                $null = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
                $result = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -EnableException -Database $db2
                $ExpectedPropsDefault = 'ComputerName,Database,DatabaseCreated,InstanceName,PrimaryFilePath,SizeMB,SnapshotOf,SqlInstance,Status'.Split(',')
                $DefaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                @($DefaultProps | Where-Object {$ExpectedPropsDefault -notcontains $_}) -Join '' | Should Be ''
            }
        }
    }
}

