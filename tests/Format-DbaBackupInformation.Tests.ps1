#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Format-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "BackupHistory",
                "ReplaceDatabaseName",
                "ReplaceDbNameInFile",
                "DataFileDirectory",
                "LogFileDirectory",
                "DestinationFileStreamDirectory",
                "DatabaseNamePrefix",
                "DatabaseFilePrefix",
                "DatabaseFileSuffix",
                "RebaseBackupFolder",
                "Continue",
                "FileMapping",
                "PathSep",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {

    Context "Rename a Database" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $history | Format-DbaBackupInformation -ReplaceDatabaseName "Pester"
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $PSItem.Database -ne "Pester" }).Count | Should -BeExactly 0
        }

        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*ContinuePointTest*" }).Count | Should -BeExactly 0
        }
    }

    Context "Test it works as a parameter as well" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -ReplaceDatabaseName "Pester"
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $PSItem.Database -ne "Pester" }).Count | Should -BeExactly 0
        }

        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "ContinuePointTest" }).Count | Should -BeExactly 0
        }
    }

    Context "Rename 2 dbs using a hash" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatReplaceName = @{
                BackupHistory       = $history
                ReplaceDatabaseName = @{
                    "ContinuePointTest" = "Spiggy"
                    "RestoreTimeClean"  = "Eldritch"
                }
            }
            $output = Format-DbaBackupInformation @splatReplaceName
        }

        It "Should have no databases other than spiggy and eldritch" {
            ($output | Where-Object { $PSItem.Database -notin ("Spiggy", "Eldritch") }).Count | Should -BeExactly 0
        }

        It "Should have renamed all RestoreTimeCleans to Eldritch" {
            $restoreTimeResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" }
            ($restoreTimeResults | Where-Object { $PSItem.Database -ne "Eldritch" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all the RestoreTimeClean files to Eldritch" {
            $restoreTimeResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" }
            $restoreTimeFileList = $restoreTimeResults | Select-Object -ExpandProperty filelist
            ($restoreTimeFileList | Where-Object { $PSItem.PhysicalName -like "RestoreTimeClean" }).Count | Should -BeExactly 0
            ($restoreTimeFileList | Where-Object { $PSItem.PhysicalName -like "eldritch" }).Count | Should -BeExactly $restoreTimeFileList.Count
        }

        It "Should have renamed all ContinuePointTest to Spiggy" {
            $continuePointResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" }
            ($continuePointResults | Where-Object { $PSItem.Database -ne "Spiggy" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all the ContinuePointTest files to Spiggy" {
            $continuePointResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" }
            $continuePointFileList = $continuePointResults | Select-Object -ExpandProperty filelist
            ($continuePointFileList | Where-Object { $PSItem.PhysicalName -like "ContinuePointTest" }).Count | Should -BeExactly 0
            ($continuePointFileList | Where-Object { $PSItem.PhysicalName -like "spiggy" }).Count | Should -BeExactly $continuePointFileList.Count
        }
    }

    Context "Rename 1 dbs using a hash" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatSingleRename = @{
                BackupHistory       = $history
                ReplaceDatabaseName = @{ "ContinuePointTest" = "Alice" }
            }
            $output = Format-DbaBackupInformation @splatSingleRename
        }

        It "Should have no databases other than RestoreTimeClean and Alice" {
            ($output | Where-Object { $PSItem.Database -notin ("RestoreTimeClean", "Alice") }).Count | Should -BeExactly 0
        }

        It "Should have left RestoreTimeClean alone" {
            $restoreTimeResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" }
            ($restoreTimeResults | Where-Object { $PSItem.Database -ne "RestoreTimeClean" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all ContinuePointTest to Alice" {
            $continuePointResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" }
            ($continuePointResults | Where-Object { $PSItem.Database -ne "Alice" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all the ContinuePointTest files to Alice" {
            $continuePointResults = $output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" }
            $continuePointFileList = $continuePointResults | Select-Object -ExpandProperty filelist
            ($continuePointFileList | Where-Object { $PSItem.PhysicalName -like "ContinuePointTest" }).Count | Should -BeExactly 0
            ($continuePointFileList | Where-Object { $PSItem.PhysicalName -like "alice" }).Count | Should -BeExactly $continuePointFileList.Count
        }
    }

    Context "Check DB Name prefix and suffix" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $history | Format-DbaBackupInformation -DatabaseNamePrefix PREFIX
        }

        It "Should have prefixed all db names" {
            ($output | Where-Object { $PSItem.Database -like "PREFIX*" }).Count | Should -BeExactly $output.Count
        }
    }

    Context "Check DataFileDirectory moves all files" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -DataFileDirectory "c:\restores"
        }

        It "Should have move ALL files to c:\restores\" {
            $allFiles = $output | Select-Object -ExpandProperty Filelist
            ($allFiles.PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\restores" }).Count | Should -BeExactly 0
        }
    }

    Context "Check DataFileDirectory and LogFileDirectory work independently" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatDirectories = @{
                BackupHistory     = $history
                DataFileDirectory = "c:\restores\"
                LogFileDirectory  = "c:\logs"
            }
            $output = Format-DbaBackupInformation @splatDirectories
        }

        It "Should have moved all data files to c:\restores\" {
            $dataFiles = $output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "D" }
            ($dataFiles.PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\restores" }).Count | Should -BeExactly 0
        }

        It "Should have moved all log files to c:\logs\" {
            $logFiles = $output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "L" }
            ($logFiles.PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\logs" }).Count | Should -BeExactly 0
        }
    }

    Context "Check LogFileDirectory works for just logfiles" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatLogDirectory = @{
                BackupHistory     = $history
                DataFileDirectory = "c:\restores\"
                LogFileDirectory  = "c:\logs"
            }
            $output = Format-DbaBackupInformation @splatLogDirectory
        }

        It "Should not have moved data files to c:\logs\" {
            $dataFiles = $output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "D" }
            ($dataFiles.PhysicalName | Split-Path | Where-Object { $PSItem -eq "c:\logs" }).Count | Should -BeExactly 0
        }

        It "Should have moved all log files to c:\logs\" {
            $logFiles = $output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "L" }
            ($logFiles.PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\logs" }).Count | Should -BeExactly 0
        }
    }

    Context "Test RebaseBackupFolder" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -RebaseBackupFolder "c:\backups\"
        }

        It "Should have moved all backup files to c:\backups" {
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $history.Count
        }
    }

    Context "Test PathSep" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
        }

        It "Should not have changed the default path separator" {
            $output = Format-DbaBackupInformation -BackupHistory $history -RebaseBackupFolder "c:\backups"
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $history.Count
        }

        It "Should not have changed the default path separator even when passed explicitly" {
            $splatDefaultSep = @{
                BackupHistory      = $history
                RebaseBackupFolder = "c:\backups"
                PathSep            = "\"
            }
            $output = Format-DbaBackupInformation @splatDefaultSep
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $history.Count
        }

        It "Should have changed the path separator as instructed" {
            $splatLinuxSep = @{
                BackupHistory      = $history
                RebaseBackupFolder = "/opt/mssql/backups"
                PathSep            = "/"
            }
            $output = Format-DbaBackupInformation @splatLinuxSep
            $result = $output | Select-Object -ExpandProperty FullName | ForEach-Object {
                $all = $PSItem.Split("/")
                $all[0..($all.Length - 2)] -Join "/"
            }
            ($result | Where-Object { $PSItem -eq "/opt/mssql/backups" }).Count | Should -BeExactly $history.Count
        }
    }

    Context "Test everything all at once" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $splatEverything = @{
                ReplaceDatabaseName = "Pester"
                DataFileDirectory   = "c:\restores"
                LogFileDirectory    = "c:\logs\"
                RebaseBackupFolder  = "c:\backups\"
            }
            $output = $history | Format-DbaBackupInformation @splatEverything
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $PSItem.Database -ne "Pester" }).Count | Should -BeExactly 0
        }

        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*ContinuePointTest*" }).Count | Should -BeExactly 0
        }

        It "Should have moved all data files to c:\restores\" {
            $dataFiles = $output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "D" }
            ($dataFiles.PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\restores" }).Count | Should -BeExactly 0
        }

        It "Should have moved all log files to c:\logs\" {
            $logFiles = $output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "L" }
            ($logFiles.PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\logs" }).Count | Should -BeExactly 0
        }

        It "Should have moved all backup files to c:\backups" {
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $history.Count
        }
    }
}