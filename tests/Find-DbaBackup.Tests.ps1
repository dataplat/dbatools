param($ModuleName = 'dbatools')

Describe "Find-DbaBackup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $testPath = "TestDrive:\sqlbackups"
        if (!(Test-Path $testPath)) {
            New-Item -Path $testPath -ItemType Container
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaBackup
        }
        It "has all the required parameters" {
            $params = @(
                "Path",
                "BackupFileExtension",
                "RetentionPeriod",
                "CheckArchiveBit",
                "EnableException"
            )
            $params | ForEach-Object {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Path validation" {
        It "Throws an exception when path is invalid" {
            { Find-DbaBackup -Path 'funnypath' -BackupFileExtension 'bak' -RetentionPeriod '0d' -EnableException } | Should -Throw "not found"
        }
    }

    Context "RetentionPeriod validation" {
        It "Throws an exception when RetentionPeriod format is invalid" {
            { Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod 'ad' -EnableException } | Should -Throw "format invalid"
        }
        It "Throws an exception when RetentionPeriod units are invalid" {
            { Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '11y' -EnableException } | Should -Throw "units invalid"
        }
    }

    Context "BackupFileExtension validation" {
        It "Does not throw when BackupFileExtension starts with a dot" {
            { Find-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' -EnableException -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "BackupFileExtension message validation" {
        It "Outputs a warning message when BackupFileExtension starts with a dot" {
            $warnmessage = Find-DbaBackup -WarningAction Continue -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' 3>&1
            $warnmessage | Should -BeLike '*period*'
        }
    }

    Context "Files found match the proper retention" {
        BeforeAll {
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
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            $results.Length | Should -Be 20
        }
        It "Should find no files '*hours*' with retention 11h" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '11h'
            $results.Length | Should -Be 15
            ($results | Where-Object FullName -Like '*hours*').Count | Should -Be 0
        }
        It "Should find no files '*days*' with retention 6d" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '6d'
            $results.Length | Should -Be 10
            ($results | Where-Object FullName -Like '*hours*').Count | Should -Be 0
            ($results | Where-Object FullName -Like '*days*').Count | Should -Be 0
        }
        It "Should find no files '*weeks*' with retention 6w" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '6w'
            $results.Length | Should -Be 5
            ($results | Where-Object FullName -Like '*hours*').Count | Should -Be 0
            ($results | Where-Object FullName -Like '*days*').Count | Should -Be 0
            ($results | Where-Object FullName -Like '*weeks*').Count | Should -Be 0
        }
        It "Should find no files '*months*' with retention 6m" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '6m'
            $results.Length | Should -Be 0
            ($results | Where-Object FullName -Like '*hours*').Count | Should -Be 0
            ($results | Where-Object FullName -Like '*days*').Count | Should -Be 0
            ($results | Where-Object FullName -Like '*weeks*').Count | Should -Be 0
            ($results | Where-Object FullName -Like '*months*').Count | Should -Be 0
        }
    }

    Context "Files found match the proper archive bit" {
        BeforeAll {
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
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            $results.Length | Should -Be 10
        }
        It "Should find only files with the archive bit not set" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d' -CheckArchiveBit
            $results.Length | Should -Be 5
            ($results | Where-Object FullName -Like '*_notarchive*').Count | Should -Be 5
            ($results | Where-Object FullName -Like '*_archive*').Count | Should -Be 0
        }
    }

    Context "Files found match the proper extension" {
        BeforeAll {
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
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'trn' -RetentionPeriod '0d'
            $results.Length | Should -Be 5
        }
        It "Should find 5 files with extension bak" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            $results.Length | Should -Be 5
        }
    }
}
