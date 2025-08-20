#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaBackup",
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
                "RemoveEmptyBackupFolder",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Confirm impact validation" {
        It "Should have medium confirm impact" {
            $command = Get-Command $CommandName
            $metadata = [System.Management.Automation.CommandMetadata]$command
            $metadata.ConfirmImpact | Should -Be "Medium"
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $testPath = "TestDrive:\sqlbackups-$(Get-Random)"
        $pathsToCleanup = @()
        if (!(Test-Path $testPath)) {
            $null = New-Item -Path $testPath -ItemType Directory
        }
        $pathsToCleanup += $testPath
    }

    AfterAll {
        Remove-Item -Path $pathsToCleanup -Recurse -ErrorAction SilentlyContinue
    }

    Context "Path validation" {
        It "Should throw when path not found" {
            { Remove-DbaBackup -Path "funnypath" -BackupFileExtension bak -RetentionPeriod "0d" -EnableException } | Should -Throw "*not found*"
        }
    }

    Context "RetentionPeriod validation" {
        It "Should throw when retention period format is invalid" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension bak -RetentionPeriod "ad" -EnableException } | Should -Throw "*format invalid*"
        }

        It "Should throw when retention period units are invalid" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension bak -RetentionPeriod "11y" -EnableException } | Should -Throw "*units invalid*"
        }
    }

    Context "BackupFileExtension validation" {
        It "Should not throw when extension starts with period" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension ".bak" -RetentionPeriod "0d" -EnableException -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "Should warn when extension starts with period" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension ".bak" -RetentionPeriod "0d" -WarningAction SilentlyContinue -WarningVariable warnmessage
            $warnmessage | Should -Match "period"
        }
    }

    Context "File removal" {
        BeforeEach {
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -Value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }

        It "Should remove all files with retention 0d" {
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension bak -RetentionPeriod "0d"
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should -Be 0
        }
    }

    Context "Extension-specific file removal" {
        BeforeEach {
            # Create .bak files
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -Value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
            # Create .trn files
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.trn"
                Set-Content $filepath -Value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }

        It "Should remove only matching extension files" {
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension bak -RetentionPeriod "0d"
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should -Be 5
            (Get-ChildItem -Path $testPath -File -Recurse).Name | Should -BeLike "*trn"
        }
    }

    Context "Empty folder cleanup" {
        BeforeEach {
            # Create empty subdirectory
            $testPathInnerEmpty = "$testPath\empty"
            if (!(Test-Path $testPathInnerEmpty)) {
                $null = New-Item -Path $testPathInnerEmpty -ItemType Directory
            }

            # Create subdirectory with files
            $testPathInner = "$testPath\inner"
            if (!(Test-Path $testPathInner)) {
                $null = New-Item -Path $testPathInner -ItemType Directory
            }

            # Create files in root test path
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -Value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }

            # Create files in inner subdirectory
            for ($i = 1; $i -le 5; $i++) {
                $filepath = Join-Path $testPathInner "dbatoolsci_$($i)_backup.bak"
                Set-Content $filepath -Value "."
                (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            }
        }

        It "Should remove files but leave empty directories by default" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension bak -RetentionPeriod "0d"
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should -Be 2
        }

        It "Should remove files and empty directories when specified" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension bak -RetentionPeriod "0d" -RemoveEmptyBackupFolder
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should -Be 0
        }
    }
}