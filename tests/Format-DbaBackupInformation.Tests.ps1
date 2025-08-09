#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Format-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $History | Format-DbaBackupInformation -ReplaceDatabaseName "Pester"
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
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = Format-DbaBackupInformation -BackupHistory $History -ReplaceDatabaseName "Pester"
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $PSItem.Database -ne "Pester" }).Count | Should -BeExactly 0
        }

        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*ContinuePointTest*" }).Count | Should -BeExactly 0
        }
    }

    Context "Rename 2 dbs using a hash" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatFormat = @{
                BackupHistory        = $History
                ReplaceDatabaseName  = @{"ContinuePointTest" = "Spiggy"; "RestoreTimeClean" = "Eldritch"}
            }
            $output = Format-DbaBackupInformation @splatFormat
        }

        It "Should have no databases other than spiggy and eldritch" {
            ($output | Where-Object { $PSItem.Database -notin ("Spiggy", "Eldritch") }).Count | Should -BeExactly 0
        }

        It "Should have renamed all RestoreTimeCleans to Eldritch" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" } | Where-Object { $PSItem.Database -ne "Eldritch" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all the RestoreTimeClean files to Eldritch" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" } | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*RestoreTimeClean*" }).Count | Should -BeExactly 0
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" } | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*eldritch*" }).Count | Should -BeExactly ($output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" } | Select-Object -ExpandProperty filelist).Count
        }

        It "Should have renamed all ContinuePointTest to Spiggy" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Where-Object { $PSItem.Database -ne "Spiggy" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all the ContinuePointTest files to Spiggy" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*ContinuePointTest*" }).Count | Should -BeExactly 0
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*spiggy*" }).Count | Should -BeExactly ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Select-Object -ExpandProperty filelist).Count
        }
    }

    Context "Rename 1 dbs using a hash" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatRename = @{
                BackupHistory       = $History
                ReplaceDatabaseName = @{"ContinuePointTest" = "Alice"}
            }
            $output = Format-DbaBackupInformation @splatRename
        }

        It "Should have no databases other than RestoreTimeClean and Alice" {
            ($output | Where-Object { $PSItem.Database -notin ("RestoreTimeClean", "Alice") }).Count | Should -BeExactly 0
        }

        It "Should have left RestoreTimeClean alone" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "RestoreTimeClean" } | Where-Object { $PSItem.Database -ne "RestoreTimeClean" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all ContinuePointTest to Alice" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Where-Object { $PSItem.Database -ne "Alice" }).Count | Should -BeExactly 0
        }

        It "Should have renamed all the ContinuePointTest files to Alice" {
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*ContinuePointTest*" }).Count | Should -BeExactly 0
            ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*alice*" }).Count | Should -BeExactly ($output | Where-Object { $PSItem.OriginalDatabase -eq "ContinuePointTest" } | Select-Object -ExpandProperty filelist).Count
        }
    }

    Context "Check DB Name prefix and suffix" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $History | Format-DbaBackupInformation -DatabaseNamePrefix PREFIX
        }

        It "Should have prefixed all db names" {
            ($output | Where-Object { $PSItem.Database -like "PREFIX*" }).Count | Should -BeExactly $output.Count
        }
    }

    Context "Check DataFileDirectory moves all files" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $History -DataFileDirectory c:\restores
        }

        It "Should have move ALL files to c:\restores\" {
            (($output | Select-Object -ExpandProperty Filelist).PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\restores" }).Count | Should -BeExactly 0
        }
    }

    Context "Check DataFileDirectory and LogFileDirectory work independently" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatDirectories = @{
                BackupHistory     = $History
                DataFileDirectory = "c:\restores\"
                LogFileDirectory  = "c:\logs"
            }
            $output = Format-DbaBackupInformation @splatDirectories
        }

        It "Should  have moved all data files to c:\restores\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "D" }).PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\restores" }).Count | Should -BeExactly 0
        }

        It "Should have moved all log files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "L" }).PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\logs" }).Count | Should -BeExactly 0
        }
    }

    Context "Check LogFileDirectory works for just logfiles" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $splatLogFiles = @{
                BackupHistory     = $History
                DataFileDirectory = "c:\restores\"
                LogFileDirectory  = "c:\logs"
            }
            $output = Format-DbaBackupInformation @splatLogFiles
        }

        It "Should not have moved all data files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "D" }).PhysicalName | Split-Path | Where-Object { $PSItem -eq "c:\logs" }).Count | Should -BeExactly 0
        }

        It "Should have moved all log files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "L" }).PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\logs" }).Count | Should -BeExactly 0
        }
    }

    Context "Test RebaseBackupFolder" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $History -RebaseBackupFolder c:\backups\
        }

        It "Should have moved all backup files to c:\backups" {
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $History.Count
        }
    }

    Context "Test PathSep" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $outputDefault = Format-DbaBackupInformation -BackupHistory $History -RebaseBackupFolder "c:\backups"
            $outputExplicit = Format-DbaBackupInformation -BackupHistory $History -RebaseBackupFolder "c:\backups" -PathSep "\"
            $splatLinux = @{
                BackupHistory      = $History
                RebaseBackupFolder = "/opt/mssql/backups"
                PathSep            = "/"
            }
            $outputLinux = Format-DbaBackupInformation @splatLinux
        }

        It "Should not have changed the default path separator" {
            ($outputDefault | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $History.Count
        }

        It "Should not have changed the default path separator even when passed explicitly" {
            ($outputExplicit | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $History.Count
        }

        It "Should have changed the path separator as instructed" {
            $result = $outputLinux | Select-Object -ExpandProperty FullName | ForEach-Object { 
                $all = $PSItem.Split("/")
                $all[0..($all.Length - 2)] -Join "/"
            }
            ($result | Where-Object { $PSItem -eq "/opt/mssql/backups" }).Count | Should -BeExactly $History.Count
        }
    }

    Context "Test everything all at once" {
        BeforeAll {
            $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $splatEverything = @{
                ReplaceDatabaseName = "Pester"
                DataFileDirectory   = "c:\restores"
                LogFileDirectory    = "c:\logs\"
                RebaseBackupFolder  = "c:\backups\"
            }
            $output = $History | Format-DbaBackupInformation @splatEverything
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $PSItem.Database -ne "Pester" }).Count | Should -BeExactly 0
        }

        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $PSItem.PhysicalName -like "*ContinuePointTest*" }).Count | Should -BeExactly 0
        }

        It "Should have moved all data files to c:\restores\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "D" }).PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\restores" }).Count | Should -BeExactly 0
        }

        It "Should have moved all log files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $PSItem.Type -eq "L" }).PhysicalName | Split-Path | Where-Object { $PSItem -ne "c:\logs" }).Count | Should -BeExactly 0
        }

        It "Should have moved all backup files to c:\backups" {
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $PSItem -eq "c:\backups" }).Count | Should -BeExactly $History.Count
        }
    }
}