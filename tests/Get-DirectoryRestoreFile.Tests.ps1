#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DirectoryRestoreFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Get-DirectoryRestoreFile.ps1"

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Recurse",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Test Path handling" {
        It "Should throw on an invalid Path" {
            { Get-DirectoryRestoreFile -Path TestDrive:\foo\bar\does\not\exist\ -EnableException } | Should -Throw
        }
    }

    Context "Returning Files from one folder" {
        BeforeAll {
            $null = New-Item "TestDrive:\backups\" -ItemType Directory
            $null = New-Item "TestDrive:\backups\full.bak" -ItemType File
            $null = New-Item "TestDrive:\backups\log1.trn" -ItemType File
            $null = New-Item "TestDrive:\backups\log2.trn" -ItemType File
            $null = New-Item "TestDrive:\backups\b\" -ItemType Directory
            $null = New-Item "TestDrive:\backups\b\log2b.trn" -ItemType File
            
            $results = Get-DirectoryRestoreFile -Path TestDrive:\backups
        }

        It "Should Return an array of FileInfo" {
            $results | Should -BeOfType System.IO.FileSystemInfo
        }

        It "Should Return 3 files" {
            $results.Count | Should -Be 3
        }

        It "Should return 1 bak file" {
            ($results | Where-Object FullName -like "*\backups\Full.bak").Count | Should -Be 1
        }

        It "Should return 2 trn files" {
            ($results | Where-Object FullName -like "*\backups\*.trn").Count | Should -Be 2
        }

        It "Should not contain log2b.trn" {
            ($results | Where-Object FullName -like "*\backups\*log2b.trn").Count | Should -Be 0
        }
    }

    Context "Returning Files from folders with recursion" {
        BeforeAll {
            $null = New-Item "TestDrive:\backups2\" -ItemType Directory
            $null = New-Item "TestDrive:\backups2\full.bak" -ItemType File
            $null = New-Item "TestDrive:\backups2\log1.trn" -ItemType File
            $null = New-Item "TestDrive:\backups2\log2.trn" -ItemType File
            $null = New-Item "TestDrive:\backups2\b\" -ItemType Directory
            $null = New-Item "TestDrive:\backups2\b\log2b.trn" -ItemType File
            
            $results2 = Get-DirectoryRestoreFile -Path TestDrive:\backups2 -Recurse
        }

        It "Should Return an array of FileInfo" {
            $results2 | Should -BeOfType System.IO.FileSystemInfo
        }

        It "Should Return 4 files" {
            $results2.Count | Should -Be 4
        }

        It "Should return 1 bak file" {
            ($results2 | Where-Object FullName -like "*\backups2\Full.bak").Count | Should -Be 1
        }

        It "Should return 3 trn files" {
            ($results2 | Where-Object FullName -like "*\backups2\*.trn").Count | Should -Be 3
        }

        It "Should contain log2b.trn" {
            ($results2 | Where-Object FullName -like "*\backups2\*log2b.trn").Count | Should -Be 1
        }
    }
}