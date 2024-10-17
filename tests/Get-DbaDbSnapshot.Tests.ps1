param($ModuleName = 'dbatools')

Describe "Get-DbaDbSnapshot Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbSnapshot
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
        It "Should have ExcludeSnapshot as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSnapshot -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

# Targets only instance2 because it's the only one where Snapshots can happen
Describe "Get-DbaDbSnapshot Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $SkipTests = [Environment]::GetEnvironmentVariable('appveyor')
    }

    Context "Operations on snapshots" -Skip:$SkipTests {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db1 = "dbatoolsci_GetSnap"
            $db1_snap1 = "dbatoolsci_GetSnap_snapshotted1"
            $db1_snap2 = "dbatoolsci_GetSnap_snapshotted2"
            $db2 = "dbatoolsci_GetSnap2"
            $db2_snap1 = "dbatoolsci_GetSnap2_snapshotted"
            Remove-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1, $db2 -Confirm:$false
            Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $null = New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1 -Name $db1_snap1 -WarningAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1 -Name $db1_snap2 -WarningAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2 -Name $db2_snap1 -WarningAction SilentlyContinue
        }
        AfterAll {
            Remove-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue -Confirm:$false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        It "Gets all snapshots by default" {
            $results = Get-DbaDbSnapshot -SqlInstance $global:instance2
            ($results | Where-Object Name -Like 'dbatoolsci_GetSnap*').Count | Should -Be 3
        }
        It "Honors the Database parameter, returning only snapshots of that database" {
            $results = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db1
            $results.Count | Should -Be 2
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2
            $result.SnapshotOf | Should -Be $db2
        }
        It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
            $alldbs = (Get-DbaDatabase -SqlInstance $global:instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
            $results = Get-DbaDbSnapshot -SqlInstance $global:instance2 -ExcludeDatabase $alldbs
            $results.Count | Should -Be 3
        }
        It "Honors the Snapshot parameter" {
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Snapshot $db1_snap1
            $result.Name | Should -Be $db1_snap1
            $result.SnapshotOf | Should -Be $db1
        }
        It "Honors the ExcludeSnapshot parameter" {
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -ExcludeSnapshot $db1_snap1 -Database $db1
            $result.Name | Should -Be $db1_snap2
        }
        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $global:instance2 -Database $db2
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}
