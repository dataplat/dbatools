#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaBackup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "BackupFileExtension",
                "RetentionPeriod",
                "CheckArchiveBit",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $testPath = "TestDrive:\sqlbackups"
        if (!(Test-Path $testPath)) {
            $null = New-Item -Path $testPath -ItemType Container
        }
    }

    Context "Path validation" {
        It "Should throw when path is not found" {
            { Find-DbaBackup -Path "funnypath" -BackupFileExtension "bak" -RetentionPeriod "0d" -EnableException } | Should -Throw "*not found*"
        }
    }

    Context "RetentionPeriod validation" {
        BeforeAll {
            $testPath = "TestDrive:\sqlbackups"
        }

        It "Should throw when retention period format is invalid" {
            { Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "ad" -EnableException } | Should -Throw "*format invalid*"
        }

        It "Should throw when retention period units are invalid" {
            { Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "11y" -EnableException } | Should -Throw "*units invalid*"
        }
    }

    Context "BackupFileExtension validation" {
        It "Should not throw when extension includes period" {
            $testPath = "TestDrive:\sqlbackups"
            { Find-DbaBackup -Path $testPath -BackupFileExtension ".bak" -RetentionPeriod "0d" -EnableException -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "BackupFileExtension message validation" {
        It "Should warn about period in extension" {
            $testPath = "TestDrive:\sqlbackups"
            $warnmessage = Find-DbaBackup -WarningAction Continue -Path $testPath -BackupFileExtension ".bak" -RetentionPeriod "0d" 3>&1
            $warnmessage | Should -BeLike "*period*"
        }
    }

    Context "Files found match the proper retention" {
        BeforeAll {
            $testPath = "TestDrive:\sqlbackups"
            if (!(Test-Path $testPath)) {
                $null = New-Item -Path $testPath -ItemType Container
            }

            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_hours.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddHours(-10)
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_days.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_weeks.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5 * 7)
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_months.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5 * 30)
            }
        }

        It "Should find all files with retention 0d" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d")
            $results.Count | Should -BeExactly 20
        }

        It "Should find no files '*hours*' with retention 11h" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "11h")
            $results.Count | Should -BeExactly 15
            ($results | Where-Object FullName -Like "*hours*").Count | Should -BeExactly 0
        }

        It "Should find no files '*days*' with retention 6d" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "6d")
            $results.Count | Should -BeExactly 10
            ($results | Where-Object FullName -Like "*hours*").Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*days*").Count | Should -BeExactly 0
        }

        It "Should find no files '*weeks*' with retention 6w" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "6w")
            $results.Count | Should -BeExactly 5
            ($results | Where-Object FullName -Like "*hours*").Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*days*").Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*weeks*").Count | Should -BeExactly 0
        }

        It "Should find no files '*months*' with retention 6m" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "6m")
            $results.Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*hours*").Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*days*").Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*weeks*").Count | Should -BeExactly 0
            ($results | Where-Object FullName -Like "*weeks*").Count | Should -BeExactly 0
        }
    }

    Context "Files found match the proper archive bit" {
        BeforeAll {
            $testPath = "TestDrive:\sqlbackups"
            if (!(Test-Path $testPath)) {
                $null = New-Item -Path $testPath -ItemType Container
            }

            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_notarchive.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
                (Get-ChildItem $filepath).Attributes = "Normal"
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_archive.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
                (Get-ChildItem $filepath).Attributes = "Archive"
            }
        }

        It "Should find all files with retention 0d" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d")
            $results.Count | Should -BeExactly 10
        }

        It "Should find only files with the archive bit not set" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d" -CheckArchiveBit)
            $results.Count | Should -BeExactly 5
            ($results | Where-Object FullName -Like "*_notarchive*").Count | Should -BeExactly 5
            ($results | Where-Object FullName -Like "*_archive*").Count | Should -BeExactly 0
        }
    }

    Context "Files found match the proper extension" {
        BeforeAll {
            $testPath = "TestDrive:\sqlbackups"
            if (!(Test-Path $testPath)) {
                $null = New-Item -Path $testPath -ItemType Container
            }

            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.trn"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }

        It "Should find 5 files with extension trn" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "trn" -RetentionPeriod "0d")
            $results.Count | Should -BeExactly 5
        }

        It "Should find 5 files with extension bak" {
            $results = @(Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d")
            $results.Count | Should -BeExactly 5
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $testPath = "TestDrive:\sqlbackups"
            if (!(Test-Path $testPath)) {
                $null = New-Item -Path $testPath -ItemType Container
            }

            $filepath = Join-Path $testPath "dbatoolsci_output_test.bak"
            Set-Content $filepath -value "test content for output validation"
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-1)

            $result = Find-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d" -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $expectedProps = @(
                'FullName',
                'Name',
                'Extension',
                'DirectoryName',
                'Length',
                'LastWriteTime',
                'Attributes',
                'CreationTime',
                'LastAccessTime'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available on FileInfo object"
            }
        }

        It "Returns files with correct extension" {
            $result.Extension | Should -Be ".bak"
        }

        It "Returns files older than retention period" {
            $result.LastWriteTime | Should -BeLessThan (Get-Date).AddDays(-1).AddMinutes(1)
        }
    }
}