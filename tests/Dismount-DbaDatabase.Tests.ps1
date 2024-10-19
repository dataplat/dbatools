param($ModuleName = 'dbatools')

Describe "Dismount-DbaDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Dismount-DbaDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have UpdateStatistics as a parameter" {
            $CommandUnderTest | Should -HaveParameter UpdateStatistics
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $dbname = "dbatoolsci_detachattach"
            $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $db1 = New-DbaDatabase -SqlInstance $global:instance3 -Name $dbname

            $fileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDbFile -SqlInstance $global:instance3 -Database $dbname).PhysicalName) {
                $null = $fileStructure.Add($file)
            }
        }

        AfterAll {
            $null = Mount-DbaDatabase -SqlInstance $global:instance3 -Database $dbname -FileStructure $fileStructure
            $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "Detaches a single database and tests to ensure the alias still exists" {
            $results = Dismount-DbaDatabase -SqlInstance $global:instance3 -Database $dbname -Force
            $results.DetachResult | Should -Be "Success"
            $results.DatabaseID | Should -Be $db1.ID
            $results.Database | Should -Be $dbname
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DatabaseID', 'DetachResult'
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        Context "Database Detachment" {
            BeforeAll {
                Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
                $server = Connect-DbaInstance -SqlInstance $global:instance3
                $db1 = "dbatoolsci_dbsetstate_detached"
                $server.Query("CREATE DATABASE $db1")
                Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
                $server = Connect-DbaInstance -SqlInstance $global:instance3
                $db2 = "dbatoolsci_dbsetstate_detached_withSnap"

                $server.Query("CREATE DATABASE $db2")
                $null = New-DbaDbSnapshot -SqlInstance $global:instance3 -Database $db2
                $fileStructure = New-Object System.Collections.Specialized.StringCollection
                foreach ($file in (Get-DbaDbFile -SqlInstance $global:instance3 -Database $db1).PhysicalName) {
                    $null = $fileStructure.Add($file)
                }
                Stop-DbaProcess -SqlInstance $global:instance3 -Database $db1
            }

            AfterAll {
                $null = Remove-DbaDbSnapshot -SqlInstance $global:instance3 -Database $db2 -Force
                $null = Mount-DbaDatabase -SqlInstance $global:instance3 -Database $db1 -FileStructure $fileStructure
                $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
            }

            It "Skips detachment if database is snapshotted" {
                $result = Dismount-DbaDatabase -SqlInstance $global:instance3 -Database $db2 -Force -WarningAction SilentlyContinue -WarningVariable warn
                $result | Should -BeNullOrEmpty
                $warn | Should -Match "snapshot"
                $result = Get-DbaDatabase -SqlInstance $global:instance3 -Database $db2
                $result | Should -Not -BeNullOrEmpty
            }

            It "Detaches the database correctly" {
                $null = Stop-DbaProcess -SqlInstance $global:instance3 -Database $db1
                $result = Dismount-DbaDatabase -SqlInstance $global:instance3 -Database $db1
                $result = Get-DbaDatabase -SqlInstance $global:instance3 -Database $db1
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
#$global:instance2 - to make it show up in appveyor, long story
