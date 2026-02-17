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
    InModuleScope dbatools {
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
                $output = Test-DbaLsnChain -FilteredRestoreFiles $filteredFiles -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
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

        Context "Transaction log chain with varying DatabaseBackupLSN (regression test for #9855)" {
            BeforeAll {
                # Create test data mimicking real scenario where transaction logs
                # have DatabaseBackupLSN matching CheckPointLSN but some don't,
                # which triggers the path that was causing NullArray exception
                $header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                # Modify one or more transaction log backups to have a different DatabaseBackupLSN
                # while maintaining valid FirstLSN to test the specific code path
                $modifiedHeader = $header | ForEach-Object {
                    $item = $_ | Select-Object *
                    # For transaction logs, set DatabaseBackupLSN different from CheckPointLSN
                    # but maintain FirstLSN > CheckPointLSN to test the fix
                    if ($item.BackupTypeDescription -eq 'Transaction Log' -and $item.FirstLSN -gt 34000000006900179) {
                        $item.DatabaseBackupLSN = 99999999999999999
                    }
                    $item
                }

                $filteredModified = $modifiedHeader | Select-DbaBackupInformation
            }

            It "Should not throw NullArray exception when filtering transaction logs" {
                # This should not throw an exception even with varying DatabaseBackupLSN values
                { Test-DbaLsnChain -FilteredRestoreFiles $filteredModified -WarningAction SilentlyContinue } | Should -Not -Throw
            }

            It "Should return Boolean result when filtering transaction logs" {
                $output = Test-DbaLsnChain -FilteredRestoreFiles $filteredModified -WarningAction SilentlyContinue
                $output | Should -BeOfType [Boolean]
            }
        }

        Context "Multiple full backups with same FirstLSN (striped backup set)" {
            BeforeAll {
                # Test scenario where multiple full backup files exist with the same FirstLSN (striped set)
                $header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
                $header | Add-Member -Type NoteProperty -Name FullName -Value 1

                # Duplicate the full backup to simulate a striped backup set
                $fullBackup = $header | Where-Object { $_.BackupTypeDescription -eq 'Database' }
                $duplicatedFull = $fullBackup | Select-Object *
                $allBackups = @($fullBackup) + @($duplicatedFull) + @($header | Where-Object { $_.BackupTypeDescription -ne 'Database' })

                $filteredStripped = $allBackups | Select-DbaBackupInformation
            }

            It "Should handle multiple full backups with same FirstLSN without error" {
                { Test-DbaLsnChain -FilteredRestoreFiles $filteredStripped -WarningAction SilentlyContinue } | Should -Not -Throw
            }

            It "Should return True for valid striped backup set" {
                $output = Test-DbaLsnChain -FilteredRestoreFiles $filteredStripped -WarningAction SilentlyContinue
                $output | Should -BeExactly $true
            }
        }

        Context "Output validation" {
            AfterAll {
                $global:dbatoolsciOutput = $null
            }

            It "Should return a Boolean" {
                $global:dbatoolsciOutput[0] | Should -BeOfType [Boolean]
            }

            It "Should have accurate .OUTPUTS documentation" {
                $help = Get-Help Test-DbaLsnChain -Full
                $help.returnValues.returnValue.type.name | Should -Match "Boolean"
            }
        }
    }
}