#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaBackup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Keys | Where-Object { $PSItem -notin ("whatif", "confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "BackupFileExtension",
                "RetentionPeriod",
                "CheckArchiveBit",
                "RemoveEmptyBackupFolder",
                "EnableException"
            )
        }

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Confirm impact should be medium" {
        BeforeAll {
            $command = Get-Command Remove-DbaBackup
            $metadata = [System.Management.Automation.CommandMetadata]$command
        }

        It "Should have medium confirm impact" {
            $metadata.ConfirmImpact | Should -Be "Medium"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testPath = "TestDrive:\sqlbackups"
        if (!(Test-Path $testPath)) {
            New-Item -Path $testPath -ItemType Container
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up test files and directories
        Remove-Item -Path $testPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Path validation" {
        It "Should throw when path does not exist" {
            { Remove-DbaBackup -Path "funnypath" -BackupFileExtension "bak" -RetentionPeriod "0d" -EnableException } | Should -Throw "not found"
        }
    }

    Context "RetentionPeriod validation" {
        It "Should throw when retention period format is invalid" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "ad" -EnableException } | Should -Throw "format invalid"
        }

        It "Should throw when retention period units are invalid" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "11y" -EnableException } | Should -Throw "units invalid"
        }
    }

    Context "BackupFileExtension validation" {
        It "Should not throw when extension starts with period" {
            { Remove-DbaBackup -Path $testPath -BackupFileExtension ".bak" -RetentionPeriod "0d" -EnableException -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "BackupFileExtension message validation" {
        It "Should warn when extension starts with period" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension ".bak" -RetentionPeriod "0d" -WarningAction SilentlyContinue -WarningVariable warnmessage
            $warnmessage | Should -Match period
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
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d"
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
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d"
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should -Be 5
            (Get-ChildItem -Path $testPath -File -Recurse).Name | Should -BeLike "*trn"
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
            Remove-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d"
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should -Be 2
        }

        It "Removes files and removes empty dirs" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension "bak" -RetentionPeriod "0d" -RemoveEmptyBackupFolder
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should -Be 0
        }
    }
}