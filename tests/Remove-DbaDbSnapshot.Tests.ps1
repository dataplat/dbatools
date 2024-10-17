param($ModuleName = 'dbatools')

Describe "Remove-DbaDbSnapshot" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbSnapshot
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Not -Mandatory
        }
        It "Should have Snapshot parameter" {
            $CommandUnderTest | Should -HaveParameter Snapshot -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have AllSnapshots parameter" {
            $CommandUnderTest | Should -HaveParameter AllSnapshots -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_RemoveSnap"
            $db1_snap1 = "dbatoolsci_RemoveSnap_snapshotted1"
            $db1_snap2 = "dbatoolsci_RemoveSnap_snapshotted2"
            $db2 = "dbatoolsci_RemoveSnap2"
            $db2_snap1 = "dbatoolsci_RemoveSnap2_snapshotted"
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
        }

        AfterAll {
            Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        Context "Parameters validation" {
            It "Stops if no Database or AllDatabases" {
                { Remove-DbaDbSnapshot -SqlInstance $script:instance2 -EnableException } | Should -Throw "You must pipe"
            }

            It "Is nice by default" {
                { Remove-DbaDbSnapshot -SqlInstance $script:instance2 *> $null } | Should -Not -Throw
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

            It "Honors the Database parameter, dropping only snapshots of that database" {
                $results = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db1 -Confirm:$false
                $results.Count | Should -Be 2
                $result = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Confirm:$false
                $result.Name | Should -Be $db2_snap1
            }

            It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
                $alldbs = (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
                $results = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -ExcludeDatabase $alldbs -Confirm:$false
                $results.Count | Should -Be 3
            }

            It "Honors the Snapshot parameter" {
                $result = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1 -Confirm:$false
                $result.Name | Should -Be $db1_snap1
            }

            It "Works with piped snapshots" {
                $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1 | Remove-DbaDbSnapshot -Confirm:$false
                $result.Name | Should -Be $db1_snap1
                $result = Get-DbaDbSnapshot -SqlInstance $script:instance2 -Snapshot $db1_snap1
                $result | Should -BeNullOrEmpty
            }

            It "Has the correct default properties" {
                $result = Remove-DbaDbSnapshot -SqlInstance $script:instance2 -Database $db2 -Confirm:$false
                $ExpectedPropsDefault = 'ComputerName', 'Name', 'InstanceName', 'SqlInstance', 'Status'
                ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
            }
        }
    }
}
