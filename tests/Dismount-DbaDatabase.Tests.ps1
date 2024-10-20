param($ModuleName = 'dbatools')

Describe "Dismount-DbaDatabase" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Dismount-DbaDatabase
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Database',
            'InputObject',
            'UpdateStatistics',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Detaches a single database and tests to ensure the alias still exists" -Tag "IntegrationTests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $dbname = "dbatoolsci_detachattach"
            $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $db1 = New-DbaDatabase -SqlInstance $global:instance3 -Name $dbname

            $global:fileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDbFile -SqlInstance $global:instance3 -Database $dbname).PhysicalName) {
                $null = $global:fileStructure.Add($file)
            }
        }

        AfterAll {
            $null = Mount-DbaDatabase -SqlInstance $global:instance3 -Database $dbname -FileStructure $global:fileStructure
            $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "Detaches the database successfully" {
            $results = Dismount-DbaDatabase -SqlInstance $global:instance3 -Database $dbname -Force
            $results.DetachResult | Should -Be "Success"
            $results.DatabaseID | Should -Be $db1.ID
            $results.Database | Should -Be $dbname
        }

        It "Has the correct properties" {
            $results = Dismount-DbaDatabase -SqlInstance $global:instance3 -Database $dbname -Force
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DatabaseID', 'DetachResult'
            $results.PSObject.Properties.Name | Should -Be $ExpectedProps
        }
    }

    Context "Database Detachment" -Tag "IntegrationTests" {
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
            $global:fileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDbFile -SqlInstance $global:instance3 -Database $db1).PhysicalName) {
                $null = $global:fileStructure.Add($file)
            }
            Stop-DbaProcess -SqlInstance $global:instance3 -Database $db1
        }

        AfterAll {
            $null = Remove-DbaDbSnapshot -SqlInstance $global:instance3 -Database $db2 -Force
            $null = Mount-DbaDatabase -SqlInstance $global:instance3 -Database $db1 -FileStructure $global:fileStructure
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
            $null = Dismount-DbaDatabase -SqlInstance $global:instance3 -Database $db1
            $result = Get-DbaDatabase -SqlInstance $global:instance3 -Database $db1
            $result | Should -BeNullOrEmpty
        }
    }
}

#$global:instance2 for appveyor
