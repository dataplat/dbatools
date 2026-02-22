#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Format-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Rename a Database" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $history | Format-DbaBackupInformation -ReplaceDatabaseName 'Pester'
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $_.Database -ne 'Pester' }).count | Should -Be 0
        }
        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*ContinuePointTest*' }).count | Should -BeGreaterThan 0
        }

    }

    Context "Test it works as a parameter as well" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -ReplaceDatabaseName 'Pester'
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $_.Database -ne 'Pester' }).count | Should -Be 0
        }
        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*ContinuePointTest*' }).count | Should -BeGreaterThan 0
        }
    }

    Context "Rename a Database using string ReplaceDatabaseName with ReplaceDbNameInFile renames log files" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -ReplaceDatabaseName 'Pester' -ReplaceDbNameInFile
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $_.Database -ne 'Pester' }).count | Should -Be 0
        }
        It "Should have renamed all data files" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $_.Type -eq 'D' } | Where-Object { $_.PhysicalName -like '*RestoreTimeClean*' }).count | Should -Be 0
        }
        It "Should have renamed all log files" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $_.Type -eq 'L' } | Where-Object { $_.PhysicalName -like '*RestoreTimeClean*' }).count | Should -Be 0
        }
        It "Log file physical name should contain new database name" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $_.Type -eq 'L' } | Where-Object { $_.PhysicalName -like '*Pester*' }).count | Should -BeGreaterThan 0
        }
    }

    Context "Rename 2 dbs using a hash" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -ReplaceDatabaseName @{'ContinuePointTest' = 'Spiggy'; 'RestoreTimeClean' = 'Eldritch' }  -ReplaceDbNameInFile
        }

        It "Should have no databases other than spiggy and eldritch" {
            ($output | Where-Object { $_.Database -notin ('Spiggy', 'Eldritch') }).count | Should -Be 0
        }
        It "Should have renamed all RestoreTimeCleans to Eldritch" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'RestoreTimeClean' } | Where-Object { $_.Database -ne 'Eldritch' }).count | Should -Be 0
        }
        It "Should have renamed all the RestoreTimeClean files to Eldritch" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'RestoreTimeClean' } | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*RestoreTimeClean*' }).count | Should -Be 0
            ($output | Where-Object { $_.OriginalDatabase -eq 'RestoreTimeClean' } | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*Eldritch*' }).count | Should -Be ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist).count
        }
        It "Should have renamed all ContinuePointTest to Spiggy" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Where-Object { $_.Database -ne 'Spiggy' }).count | Should -Be 0
        }
        It "Should have renamed all the ContinuePointTest files to Spiggy" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*ContinuePointTest*' }).count | Should -Be 0
            ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*Spiggy*' }).count | Should -Be ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist).count
        }
    }

    Context "Rename 1 dbs using a hash" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -ReplaceDatabaseName @{'ContinuePointTest' = 'Alice' } -ReplaceDbNameInFile
        }

        It "Should have no databases other than spiggy and eldritch" {
            ($output | Where-Object { $_.Database -notin ('RestoreTimeClean', 'Alice') }).count | Should -Be 0
        }
        It "Should have left RestoreTimeClean alone" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'RestoreTimeClean' } | Where-Object { $_.Database -ne 'RestoreTimeClean' }).count | Should -Be 0
        }
        It "Should have renamed all ContinuePointTest to Alice" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Where-Object { $_.Database -ne 'Alice' }).count | Should -Be 0
        }
        It "Should have renamed all the ContinuePointTest files to Alice" {
            ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*ContinuePointTest*' }).count | Should -Be 0
            ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*Alice*' }).count | Should -Be ($output | Where-Object { $_.OriginalDatabase -eq 'ContinuePointTest' } | Select-Object -ExpandProperty filelist).count
        }
    }

    Context "Check DB Name prefix and suffix" {
        It "Should have prefixed all db names" {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $history | Format-DbaBackupInformation -DatabaseNamePrefix PREFIX
            ($output | Where-Object { $_.Database -like 'PREFIX*' }).count | Should -Be $output.count
        }

    }

    Context "Check DataFileDirectory moves all files" {
        It "Should have move ALL files to c:\restores\" {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -DataFileDirectory c:\restores
            (($output | Select-Object -ExpandProperty Filelist).PhysicalName | Split-Path | Where-Object { $_ -ne 'c:\restores' }).count | Should -Be 0
        }
    }

    Context "Check DataFileDirectory and LogFileDirectory work independently" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -DataFileDirectory c:\restores\ -LogFileDirectory c:\logs
        }

        It "Should  have moved all data files to c:\restores\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $_.Type -eq 'D' }).PhysicalName | Split-Path | Where-Object { $_ -ne 'c:\restores' }).count | Should -Be 0
        }
        It "Should have moved all log files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $_.Type -eq 'L' }).PhysicalName | Split-Path | Where-Object { $_ -ne 'c:\logs' }).count | Should -Be 0
        }
    }

    Context "Check LogFileDirectory works for just logfiles" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -DataFileDirectory c:\restores\ -LogFileDirectory c:\logs
        }

        It "Should not have moved all data files to c:\restores\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $_.Type -eq 'D' }).PhysicalName | Split-Path | Where-Object { $_ -eq 'c:\logs' }).count | Should -Be 0
        }
        It "Should have moved all log files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $_.Type -eq 'L' }).PhysicalName | Split-Path | Where-Object { $_ -ne 'c:\logs' }).count | Should -Be 0
        }
    }

    Context "Test RebaseBackupFolder" {
        It "Should not have moved all backup files to c:\backups" {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
            $output = Format-DbaBackupInformation -BackupHistory $history -RebaseBackupFolder c:\backups\
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $_ -eq 'c:\backups' }).count | Should -Be $history.count
        }

    }

    Context "Test PathSep" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $history += Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
        }

        It "Should not have changed the default path separator" {
            $output = Format-DbaBackupInformation -BackupHistory $history -RebaseBackupFolder 'c:\backups'
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $_ -eq 'c:\backups' }).count | Should -Be $history.count
        }
        It "Should not have changed the default path separator even when passed explicitely" {
            $output = Format-DbaBackupInformation -BackupHistory $history -RebaseBackupFolder 'c:\backups' -PathSep '\'
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $_ -eq 'c:\backups' }).count | Should -Be $history.count
        }
        It "Should have changed the path separator as instructed" {
            $output = Format-DbaBackupInformation -BackupHistory $history -RebaseBackupFolder '/opt/mssql/backups' -PathSep '/'
            $result = $output | Select-Object -ExpandProperty FullName | ForEach-Object { $all = $_.Split('/'); $all[0..($all.Length - 2)] -Join '/' }
            ($result | Where-Object { $_ -eq '/opt/mssql/backups' }).count | Should -Be $history.count
        }
    }

    Context "Test everything all at once" {
        BeforeAll {
            $history = Get-DbaBackupInformation -Import -Path $PSScriptRoot\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
            $output = $history | Format-DbaBackupInformation -ReplaceDatabaseName 'Pester' -DataFileDirectory c:\restores -LogFileDirectory c:\logs\ -RebaseBackupFolder c:\backups\
        }

        It "Should have a database name of Pester" {
            ($output | Where-Object { $_.Database -ne 'Pester' }).count | Should -Be 0
        }
        It "Should have renamed datafiles as well" {
            ($output | Select-Object -ExpandProperty filelist | Where-Object { $_.PhysicalName -like '*ContinuePointTest*' }).count | Should -BeGreaterThan 0
        }
        It "Should have moved all data files to c:\restores\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $_.Type -eq 'D' }).PhysicalName | Split-Path | Where-Object { $_ -ne 'c:\restores' }).count | Should -Be 0
        }
        It "Should have moved all log files to c:\logs\" {
            (($output | Select-Object -ExpandProperty Filelist | Where-Object { $_.Type -eq 'L' }).PhysicalName | Split-Path | Where-Object { $_ -ne 'c:\logs' }).count | Should -Be 0
        }
        It "Should not have moved all backup files to c:\backups" {
            ($output | Select-Object -ExpandProperty FullName | Split-Path | Where-Object { $_ -eq 'c:\backups' }).count | Should -Be $history.count
        }
    }
}