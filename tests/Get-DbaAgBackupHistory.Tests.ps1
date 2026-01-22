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

    Context "Output Validation" {
        BeforeAll {
            # Note: This test requires an actual AG setup which isn't available in CI
            # These tests validate the expected output structure documentation
            $help = Get-Help $CommandName -Full
        }

        It "Should document Dataplat.Dbatools.Database.BackupHistory in .OUTPUTS section" {
            $help.returnValues.returnValue.type.name | Should -Be 'Dataplat.Dbatools.Database.BackupHistory'
        }

        It "Should document the output description" {
            $help.returnValues.returnValue.description | Should -Not -BeNullOrEmpty
            $outputText = ($help.returnValues.returnValue.description | ForEach-Object { $_.Text }) -join ''
            $outputText | Should -Match 'backup history'
        }

        It "Should document default display properties" {
            # Get the full help text that contains property documentation
            $fullHelpText = ($help.returnValues.returnValue.description | ForEach-Object { $_.Text }) -join ''
            
            # Documented default properties should be mentioned
            $fullHelpText | Should -Match 'SqlInstance'
            $fullHelpText | Should -Match 'Database'
            $fullHelpText | Should -Match 'Type'
            $fullHelpText | Should -Match 'TotalSize'
        }

        It "Should document AvailabilityGroupName property specific to this command" {
            $fullHelpText = ($help.returnValues.returnValue.description | ForEach-Object { $_.Text }) -join ''
            $fullHelpText | Should -Match 'AvailabilityGroupName' -Because "this command adds AG context to backup history"
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor