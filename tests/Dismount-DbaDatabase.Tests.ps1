param($ModuleName = 'dbatools')

Describe "Dismount-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Dismount-DbaDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have UpdateStatistics as a parameter" {
            $CommandUnderTest | Should -HaveParameter UpdateStatistics -Type SwitchParameter
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $dbname = "dbatoolsci_detachattach"
            $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $db1 = New-DbaDatabase -SqlInstance $script:instance3 -Name $dbname

            $fileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDbFile -SqlInstance $script:instance3 -Database $dbname).PhysicalName) {
                $null = $fileStructure.Add($file)
            }
        }

        AfterAll {
            $null = Mount-DbaDatabase -SqlInstance $script:instance3 -Database $dbname -FileStructure $fileStructure
            $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "Detaches a single database and tests to ensure the alias still exists" {
            $results = Dismount-DbaDatabase -SqlInstance $script:instance3 -Database $dbname -Force
            $results.DetachResult | Should -Be "Success"
            $results.DatabaseID | Should -Be $db1.ID
            $results.Database | Should -Be $dbname
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DatabaseID', 'DetachResult'
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        Context "Database Detachment" {
            BeforeAll {
                Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
                $server = Connect-DbaInstance -SqlInstance $script:instance3
                $db1 = "dbatoolsci_dbsetstate_detached"
                $server.Query("CREATE DATABASE $db1")
                Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
                $server = Connect-DbaInstance -SqlInstance $script:instance3
                $db2 = "dbatoolsci_dbsetstate_detached_withSnap"

                $server.Query("CREATE DATABASE $db2")
                $null = New-DbaDbSnapshot -SqlInstance $script:instance3 -Database $db2
                $fileStructure = New-Object System.Collections.Specialized.StringCollection
                foreach ($file in (Get-DbaDbFile -SqlInstance $script:instance3 -Database $db1).PhysicalName) {
                    $null = $fileStructure.Add($file)
                }
                Stop-DbaProcess -SqlInstance $script:instance3 -Database $db1
            }

            AfterAll {
                $null = Remove-DbaDbSnapshot -SqlInstance $script:instance3 -Database $db2 -Force
                $null = Mount-DbaDatabase -SqlInstance $script:instance3 -Database $db1 -FileStructure $fileStructure
                $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            }

            It "Skips detachment if database is snapshotted" {
                $result = Dismount-DbaDatabase -SqlInstance $script:instance3 -Database $db2 -Force -WarningAction SilentlyContinue -WarningVariable warn
                $result | Should -BeNullOrEmpty
                $warn | Should -Match "snapshot"
                $result = Get-DbaDatabase -SqlInstance $script:instance3 -Database $db2
                $result | Should -Not -BeNullOrEmpty
            }

            It "Detaches the database correctly" {
                $null = Stop-DbaProcess -SqlInstance $script:instance3 -Database $db1
                $result = Dismount-DbaDatabase -SqlInstance $script:instance3 -Database $db1
                $result = Get-DbaDatabase -SqlInstance $script:instance3 -Database $db1
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
#$script:instance2 - to make it show up in appveyor, long story
