$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Test Path handling" {
        It "Should throw on an invalid Path" {
            { Get-DirectoryRestoreFile -Path TestDrive:\foo\bar\does\not\exist\ -EnableException } | Should Throw
        }
    }
    Context "Returning Files from one folder" {
        New-item "TestDrive:\backups\" -ItemType directory
        New-item "TestDrive:\backups\full.bak" -ItemType File
        New-item "TestDrive:\backups\log1.trn" -ItemType File
        New-item "TestDrive:\backups\log2.trn" -ItemType File
        New-item "TestDrive:\backups\b\" -ItemType directory
        New-item "TestDrive:\backups\b\log2b.trn" -ItemType File
        $results = Get-DirectoryRestoreFile -Path TestDrive:\backups
        It "Should Return an array of FileInfo" {
            $results | Should BeOfType System.IO.FileSystemInfo
        }
        It "Should Return 3 files" {
            $results.count | Should Be 3
        }
        It "Should return 1 bak file" {
            ($results | Where-Object { $_.Fullname -like '*\backups\Full.bak' }).count | Should be 1
        }
        It "Should return 2 trn files" {
            ($results | Where-Object { $_.Fullname -like '*\backups\*.trn' }).count | Should be 2
        }
        It "Should not contain log2b.trn" {
            ($results | Where-Object { $_.Fullname -like '*\backups\*log2b.trn' }).count | Should be 0
        }
    }
    Context "Returning Files from folders with recursion" {
        New-item "TestDrive:\backups\" -ItemType directory
        New-item "TestDrive:\backups\full.bak" -ItemType File
        New-item "TestDrive:\backups\log1.trn" -ItemType File
        New-item "TestDrive:\backups\log2.trn" -ItemType File
        New-item "TestDrive:\backups\b\" -ItemType directory
        New-item "TestDrive:\backups\b\log2b.trn" -ItemType File
        $results2 = Get-DirectoryRestoreFile -Path TestDrive:\backups -recurse
        It "Should Return an array of FileInfo" {
            $results2 | Should BeOfType System.IO.FileSystemInfo
        }
        It "Should Return 4 files" {
            $results2.count | Should Be 4
        }
        It "Should return 1 bak file" {
            ($results2 | Where-Object {$_.Fullname -like '*\backups\Full.bak'}).count | Should be 1
        }
        It "Should return 3 trn files" {
            ($results2 | Where-Object {$_.Fullname -like '*\backups\*.trn'}).count | Should be 3
        }
        It "Should  contain log2b.trn" {
            ($results2 | Where-Object {$_.Fullname -like '*\backups\*log2b.trn'}).count | Should be 1
        }
    }
}
