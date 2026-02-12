#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgBackupHistory",
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
                "AvailabilityGroup",
                "Database",
                "ExcludeDatabase",
                "IncludeCopyOnly",
                "Force",
                "Since",
                "RecoveryFork",
                "Last",
                "LastFull",
                "LastDiff",
                "LastLog",
                "DeviceType",
                "Raw",
                "LastLsn",
                "IncludeMirror",
                "Type",
                "LsnSort",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $agName = (Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -ErrorAction SilentlyContinue).Name | Select-Object -First 1
            if ($agName) {
                $result = Get-DbaAgBackupHistory -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -Last -ErrorAction SilentlyContinue
            }
        }

        It "Returns output of the documented type" {
            if (-not $agName) { Set-ItResult -Skipped -Because "no availability group found on the instance" }
            if (-not $result) { Set-ItResult -Skipped -Because "no backup history available for the AG" }
            $result[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Database.BackupHistory"
        }

        It "Has the AvailabilityGroupName property added by the function" {
            if (-not $agName) { Set-ItResult -Skipped -Because "no availability group found on the instance" }
            if (-not $result) { Set-ItResult -Skipped -Because "no backup history available for the AG" }
            $result[0].psobject.Properties["AvailabilityGroupName"] | Should -Not -BeNullOrEmpty
            $result[0].AvailabilityGroupName | Should -Be $agName
        }

        It "Has the core backup history properties" {
            if (-not $agName) { Set-ItResult -Skipped -Because "no availability group found on the instance" }
            if (-not $result) { Set-ItResult -Skipped -Because "no backup history available for the AG" }
            $coreProperties = @("SqlInstance", "Database", "Type", "TotalSize", "DeviceType", "Start", "End")
            foreach ($prop in $coreProperties) {
                $result[0].psobject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on the backup history object"
            }
        }
    }
}