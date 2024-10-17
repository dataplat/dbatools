param($ModuleName = 'dbatools')

Describe "Get-DirectoryRestoreFile" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Get-DirectoryRestoreFile.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DirectoryRestoreFile
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have Recurse as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Recurse -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Test Path handling" {
        It "Should throw on an invalid Path" {
            { Get-DirectoryRestoreFile -Path TestDrive:\foo\bar\does\not\exist\ -EnableException } | Should -Throw
        }
    }

    Context "Returning Files from one folder" {
        BeforeAll {
            New-Item "TestDrive:\backups\" -ItemType Directory
            New-Item "TestDrive:\backups\full.bak" -ItemType File
            New-Item "TestDrive:\backups\log1.trn" -ItemType File
            New-Item "TestDrive:\backups\log2.trn" -ItemType File
            New-Item "TestDrive:\backups\b\" -ItemType Directory
            New-Item "TestDrive:\backups\b\log2b.trn" -ItemType File
            $results = Get-DirectoryRestoreFile -Path TestDrive:\backups
        }

        It "Should Return an array of FileInfo" {
            $results | Should -BeOfType System.IO.FileSystemInfo
        }
        It "Should Return 3 files" {
            $results.Count | Should -Be 3
        }
        It "Should return 1 bak file" {
            ($results | Where-Object { $_.FullName -like '*\backups\Full.bak' }).Count | Should -Be 1
        }
        It "Should return 2 trn files" {
            ($results | Where-Object { $_.FullName -like '*\backups\*.trn' }).Count | Should -Be 2
        }
        It "Should not contain log2b.trn" {
            ($results | Where-Object { $_.FullName -like '*\backups\*log2b.trn' }).Count | Should -Be 0
        }
    }

    Context "Returning Files from folders with recursion" {
        BeforeAll {
            New-Item "TestDrive:\backups\" -ItemType Directory
            New-Item "TestDrive:\backups\full.bak" -ItemType File
            New-Item "TestDrive:\backups\log1.trn" -ItemType File
            New-Item "TestDrive:\backups\log2.trn" -ItemType File
            New-Item "TestDrive:\backups\b\" -ItemType Directory
            New-Item "TestDrive:\backups\b\log2b.trn" -ItemType File
            $results2 = Get-DirectoryRestoreFile -Path TestDrive:\backups -Recurse
        }

        It "Should Return an array of FileInfo" {
            $results2 | Should -BeOfType System.IO.FileSystemInfo
        }
        It "Should Return 4 files" {
            $results2.Count | Should -Be 4
        }
        It "Should return 1 bak file" {
            ($results2 | Where-Object { $_.FullName -like '*\backups\Full.bak' }).Count | Should -Be 1
        }
        It "Should return 3 trn files" {
            ($results2 | Where-Object { $_.FullName -like '*\backups\*.trn' }).Count | Should -Be 3
        }
        It "Should contain log2b.trn" {
            ($results2 | Where-Object { $_.FullName -like '*\backups\*log2b.trn' }).Count | Should -Be 1
        }
    }
}
