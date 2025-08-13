#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLsnChain",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Test-DbaLsnChain.ps1"

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FilteredRestoreFiles",
                "Continue",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    InModuleScope dbatools {
        Context "General Diff restore" {
            BeforeAll {
                $jsonHeader = ConvertFrom-Json -InputObject (Get-Content "$PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json" -Raw)
                $jsonHeader | Add-Member -Type NoteProperty -Name FullName -Value 1

                $filteredFilesWithDiff = $jsonHeader | Select-DbaBackupInformation
                
                $jsonHeaderNoDiff = ConvertFrom-Json -InputObject (Get-Content "$PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json" -Raw)
                $jsonHeaderNoDiff = $jsonHeaderNoDiff | Where-Object BackupTypeDescription -ne "Database Differential"
                $jsonHeaderNoDiff | Add-Member -Type NoteProperty -Name FullName -Value 1

                $filteredFilesNoDiff = $jsonHeaderNoDiff | Select-DbaBackupInformation
            }

            It "Should Return 7" {
                $filteredFilesWithDiff.Count | Should -Be 7
            }

            It "Should return True" {
                $output = Test-DbaLsnChain -FilteredRestoreFiles $filteredFilesWithDiff -WarningAction SilentlyContinue
                $output | Should -Be $true
            }

            It "Should return true if we remove diff backup" {
                $filteredFilesRemovedDiff = $filteredFilesWithDiff | Where-Object BackupTypeDescription -ne "Database Differential"
                $output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles $filteredFilesRemovedDiff
                $output | Should -Be $true
            }

            It "Should return False (faked lsn)" {
                $testFilteredFiles = $filteredFilesWithDiff.Clone()
                $testFilteredFiles[4].FirstLsn = 2
                $testFilteredFiles[4].LastLsn = 1
                $output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles $testFilteredFiles
                $output | Should -Be $false
            }
        }
    }
}