param($ModuleName = 'dbatools')

Describe "Remove-DbaBackup" {
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
            $CommandUnderTest = Get-Command Remove-DbaBackup
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Path",
                "BackupFileExtension",
                "RetentionPeriod",
                "CheckArchiveBit",
                "RemoveEmptyBackupFolder",
                "EnableException"
            )
            $requiredParameters | ForEach-Object {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Confirm impact" {
        It "Should have Confirm impact set to Medium" {
            $command = Get-Command Remove-DbaBackup
            $metadata = [System.Management.Automation.CommandMetadata]$command
            $metadata.ConfirmImpact | Should -Be 'Medium'
        }
    }

    Context "Path validation" {
        It "Should throw when path is invalid" {
            { Remove-DbaBackup -Path 'funnypath' -BackupFileExtension 'bak' -RetentionPeriod '0d' -EnableException } | Should -Throw "not found"
        }
    }

    Context "RetentionPeriod validation" {
        It "Should throw when RetentionPeriod format is invalid" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod 'ad' -EnableException } | Should -Throw "format invalid"
        }
        It "Should throw when RetentionPeriod units are invalid" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '11y' -EnableException } | Should -Throw "units invalid"
        }
    }

    Context "BackupFileExtension validation" {
        It "Should not throw when BackupFileExtension starts with a period" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' -EnableException -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "BackupFileExtension message validation" {
        It "Should warn when BackupFileExtension starts with a period" {
            $warnMessage = $null
            Remove-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' -WarningAction SilentlyContinue -WarningVariable warnMessage
            $warnMessage | Should -Match period
        }
    }

    Context "Files are removed" {
        BeforeAll {
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }
        It "Should remove all files with retention 0d" {
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should -Be 0
        }
    }

    Context "Files with matching extensions only are removed" {
        BeforeAll {
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.trn"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }
        It "Should remove all files but not the trn ones" {
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should -Be 5
            (Get-ChildItem -Path $testPath -File -Recurse).Name | Should -BeLike '*trn'
        }
    }

    Context "Cleanup empty folders" {
        BeforeAll {
            $testPathinner_empty = "TestDrive:\sqlbackups\empty"
            if (!(Test-Path $testPathinner_empty)) {
                New-Item -Path $testPathinner_empty -ItemType Container
            }
            $testPathinner = "TestDrive:\sqlbackups\inner"
            if (!(Test-Path $testPathinner)) {
                New-Item -Path $testPathinner -ItemType Container
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPathinner "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }
        It "Removes files but leaves empty dirs" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should -Be 2
        }
        It "Removes files and removes empty dirs" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d' -RemoveEmptyBackupFolder
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should -Be 0
        }
    }
}
