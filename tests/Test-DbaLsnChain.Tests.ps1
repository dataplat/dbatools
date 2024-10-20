param($ModuleName = 'dbatools')

Describe "Test-DbaLsnChain" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Test-DbaLsnChain.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaLsnChain
        }

        $params = @(
            "FilteredRestoreFiles",
            "Continue",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "General Diff restore" {
        BeforeAll {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1

            $filteredFiles = $header | Select-DbaBackupInformation
        }

        It "Should Return 7" {
            $filteredFiles.count | Should -Be 7
        }

        It "Should return True" {
            $Output = Test-DbaLsnChain -FilteredRestoreFiles $filteredFiles -WarningAction SilentlyContinue
            $Output | Should -BeTrue
        }

        It "Should return true if we remove diff backup" {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header = $Header | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' }
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1

            $FilteredFiles = $Header | Select-DbaBackupInformation
            $Output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles ($FilteredFiles | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' })
            $Output | Should -BeTrue
        }

        It "Should return False (faked lsn)" {
            $FilteredFiles[4].FirstLsn = 2
            $FilteredFiles[4].LastLsn = 1
            $Output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles $FilteredFiles
            $Output | Should -BeFalse
        }
    }
}
