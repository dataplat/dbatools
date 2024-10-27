#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Dismount-DbaDatabase" -Tag "UnitTests" {
    BeforeAll {
        $command = Get-Command Dismount-DbaDatabase
        $expected = $TestConfig.CommonParameters
        $expected += @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "InputObject",
            "UpdateStatistics",
            "Force",
            "EnableException",
            "Confirm",
            "WhatIf"
        )
    }
    Context "Parameter validation" {
        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Dismount-DbaDatabase" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue

        $dbName = "dbatoolsci_detachattach"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName | Remove-DbaDatabase -Confirm:$false
        $database = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $dbName

        $global:fileStructure = New-Object System.Collections.Specialized.StringCollection
        foreach ($file in (Get-DbaDbFile -SqlInstance $TestConfig.instance3 -Database $dbName).PhysicalName) {
            $null = $fileStructure.Add($file)
        }
    }

    AfterAll {
        $null = Mount-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -FileStructure $fileStructure
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName | Remove-DbaDatabase -Confirm:$false
    }

    Context "When detaching a single database" {
        BeforeAll {
            $results = Dismount-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Force
        }

        It "Should complete successfully" {
            $results.DetachResult | Should -Be "Success"
            $results.DatabaseID | Should -Be $database.ID
        }

        It "Should remove just one database" {
            $results.Database | Should -Be $dbName
        }
    }

    Context "When detaching databases with snapshots" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
            $dbDetached = "dbatoolsci_dbsetstate_detached"
            $dbWithSnapshot = "dbatoolsci_dbsetstate_detached_withSnap"

            $server.Query("CREATE DATABASE $dbDetached")
            $server.Query("CREATE DATABASE $dbWithSnapshot")

            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.instance3 -Database $dbWithSnapshot

            $splatFileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDbFile -SqlInstance $TestConfig.instance3 -Database $dbDetached).PhysicalName) {
                $null = $splatFileStructure.Add($file)
            }

            Stop-DbaProcess -SqlInstance $TestConfig.instance3 -Database $dbDetached
        }

        AfterAll {
            $null = Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance3 -Database $dbWithSnapshot -Force
            $null = Mount-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbDetached -FileStructure $splatFileStructure
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbDetached, $dbWithSnapshot | Remove-DbaDatabase -Confirm:$false
        }

        It "Should skip detachment if database has snapshots" {
            $result = Dismount-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbWithSnapshot -Force -WarningAction SilentlyContinue -WarningVariable warn 3> $null
            $result | Should -BeNullOrEmpty
            $warn | Should -Match "snapshot"

            $database = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbWithSnapshot
            $database | Should -Not -BeNullOrEmpty
        }

        It "Should detach database without snapshots" {
            # skip for now in appveyor, but when we do troubleshoot, maybe it just needs a sleep
            Start-Sleep 3
            $null = Stop-DbaProcess -SqlInstance $TestConfig.instance3 -Database $dbDetached
            $null = Dismount-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbDetached
            $result = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbDetached
            $result | Should -BeNullOrEmpty
        }
    }
}
#$TestConfig.instance2 - to make it show up in appveyor, long story
