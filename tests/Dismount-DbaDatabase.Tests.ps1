#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Dismount-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "UpdateStatistics",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue

        $dbName = "dbatoolsci_detachattach"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName | Remove-DbaDatabase
        $database = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

        $fileStructure = New-Object System.Collections.Specialized.StringCollection
        foreach ($file in (Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $dbName).PhysicalName) {
            $null = $fileStructure.Add($file)
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Mount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -FileStructure $fileStructure
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When detaching a single database" {
        BeforeAll {
            $results = Dismount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Force
        }

        It "Should complete successfully" {
            $results.DetachResult | Should -Be "Success"
            $results.DatabaseID | Should -Be $database.ID
        }

        It "Should remove just one database" {
            $results.Database | Should -Be $dbName
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $results | Should -Not -BeNullOrEmpty
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseID", "DetachResult")
            foreach ($prop in $expectedProperties) {
                $results.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }

    Context "When detaching databases with snapshots" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $dbDetached = "dbatoolsci_dbsetstate_detached"
            $dbWithSnapshot = "dbatoolsci_dbsetstate_detached_withSnap"

            $server.Query("CREATE DATABASE $dbDetached")
            $server.Query("CREATE DATABASE $dbWithSnapshot")

            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $dbWithSnapshot

            $splatFileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached).PhysicalName) {
                $null = $splatFileStructure.Add($file)
            }

            Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached
        }

        AfterAll {
            $null = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $dbWithSnapshot -Force -ErrorAction SilentlyContinue
            $null = Mount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached -FileStructure $splatFileStructure -ErrorAction SilentlyContinue
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached, $dbWithSnapshot | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }

        It "Should skip detachment if database has snapshots" {
            $result = Dismount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbWithSnapshot -Force -WarningAction SilentlyContinue -WarningVariable warn 3> $null
            $result | Should -BeNullOrEmpty
            $warn | Should -Match "snapshot"

            $database = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbWithSnapshot
            $database | Should -Not -BeNullOrEmpty
        }

        It "Should detach database without snapshots" {
            Start-Sleep 3
            $null = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached
            $null = Dismount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached
            $result = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbDetached
            $result | Should -BeNullOrEmpty
        }
    }

}