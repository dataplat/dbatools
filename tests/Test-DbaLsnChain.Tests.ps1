#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLsnChain",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FilteredRestoreFiles",
                "Continue",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "General Diff restore" {
        BeforeAll {
            $header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1

            $filteredFiles = $header | Select-DbaBackupInformation

            $headerNoDiff = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $headerNoDiff = $headerNoDiff | Where-Object BackupTypeDescription -ne "Database Differential"
            $headerNoDiff | Add-Member -Type NoteProperty -Name FullName -Value 1

            $filteredFilesNoDiff = $headerNoDiff | Select-DbaBackupInformation
        }

        It "Should Return 7" {
            $filteredFiles.count | Should -BeExactly 7
        }

        It "Should return True" {
            $output = Test-DbaLsnChain -FilteredRestoreFiles $filteredFiles -WarningAction SilentlyContinue
            $output | Should -BeExactly $true
        }

        It "Should return true if we remove diff backup" {
            $output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles ($filteredFilesNoDiff | Where-Object BackupTypeDescription -ne "Database Differential")
            $output | Should -BeExactly $true
        }

        It "Should return False (faked lsn)" {
            $filteredFiles[4].FirstLsn = 2
            $filteredFiles[4].LastLsn = 1
            $output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles $filteredFiles
            $output | Should -BeExactly $false
        }
    }
}