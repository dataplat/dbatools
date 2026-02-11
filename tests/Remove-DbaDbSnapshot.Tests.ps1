#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbSnapshot",
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
                "ExcludeDatabase",
                "Snapshot",
                "InputObject",
                "AllSnapshots",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $db1 = "dbatoolsci_RemoveSnap"
        $db1_snap1 = "dbatoolsci_RemoveSnap_snapshotted1"
        $db1_snap2 = "dbatoolsci_RemoveSnap_snapshotted2"
        $db2 = "dbatoolsci_RemoveSnap2"
        $db2_snap1 = "dbatoolsci_RemoveSnap2_snapshotted"
        Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 | Remove-DbaDatabase
        $server.Query("CREATE DATABASE $db1")
        $server.Query("CREATE DATABASE $db2")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Parameters validation" {
        It "Stops if no Database or AllDatabases" {
            { Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -EnableException -WarningAction SilentlyContinue } | Should -Throw "You must pipe*"
        }
        It "Is nice by default" {
            { Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle *> $null } | Should -Not -Throw "You must pipe*"
        }
    }

    Context "Operations on snapshots" {
        BeforeEach {
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name $db1_snap1 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name $db1_snap2 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2 -Name $db2_snap1 -ErrorAction SilentlyContinue
        }
        AfterEach {
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        It "Honors the Database parameter, dropping only snapshots of that database" {
            $results = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1
            $results.Count | Should -Be 2
            $result = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $result.Name | Should -Be $db2_snap1
        }

        It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
            $alldbs = (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
            $results = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $alldbs
            $results.Count | Should -Be 3
        }
        It "Honors the Snapshot parameter" {
            $result = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1
            $result.Name | Should -Be $db1_snap1
        }
        It "Works with piped snapshots" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1 | Remove-DbaDbSnapshot
            $result.Name | Should -Be $db1_snap1
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1
            $result | Should -BeNullOrEmpty
        }
        It "Has the correct default properties" {
            $result = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $ExpectedPropsDefault = 'ComputerName', 'Name', 'InstanceName', 'SqlInstance', 'Status'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }

    Context "Output validation" {
        BeforeAll {
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name "dbatoolsci_RemoveSnap_outputtest" -ErrorAction SilentlyContinue
            $outputResult = Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot "dbatoolsci_RemoveSnap_outputtest"
        }

        It "Returns output of the expected type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has working alias property Name mapped from Database" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].PSObject.Properties["Name"] | Should -Not -BeNullOrEmpty
            $outputResult[0].PSObject.Properties["Name"].MemberType | Should -Be "AliasProperty"
        }
    }
}