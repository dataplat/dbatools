#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DirectoryRestoreFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Recurse",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        . "$PSScriptRoot\..\private\functions\Get-DirectoryRestoreFile.ps1"
    }

    Context "Test Path handling" {
        It "Should throw on an invalid Path" {
            { Get-DirectoryRestoreFile -Path "TestDrive:\foo\bar\does\not\exist\" -EnableException } | Should -Throw
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
            $results = Get-DirectoryRestoreFile -Path "TestDrive:\backups" -OutVariable "global:dbatoolsciOutput"
        }

        AfterAll {
            Remove-Item -Path "TestDrive:\backups" -Recurse -ErrorAction SilentlyContinue
        }

        It "Should Return an array of FileInfo" {
            $results | Should -BeOfType System.IO.FileSystemInfo
            $results | Should -BeOfType System.IO.FileSystemInfo
        }


        It "Should Return 3 files" {
            $results.count | Should -Be 3
        }


        It "Should return 1 bak file" {
            ($results | Where-Object FullName -like "*\backups\Full.bak").count | Should -Be 1
        }


        It "Should return 2 trn files" {
            ($results | Where-Object FullName -like "*\backups\*.trn").count | Should -Be 2
        }


        It "Should not contain log2b.trn" {
            ($results | Where-Object FullName -like "*\backups\*log2b.trn").count | Should -Be 0
        }
    }


    Context "Returning Files from folders with recursion" {
        BeforeAll {
            $null = New-Item "TestDrive:\backupsRecurse\" -ItemType Directory
            $null = New-Item "TestDrive:\backupsRecurse\full.bak" -ItemType File
            $null = New-Item "TestDrive:\backupsRecurse\log1.trn" -ItemType File
            $null = New-Item "TestDrive:\backupsRecurse\log2.trn" -ItemType File
            $null = New-Item "TestDrive:\backupsRecurse\b\" -ItemType Directory
            $null = New-Item "TestDrive:\backupsRecurse\b\log2b.trn" -ItemType File
            $results2 = Get-DirectoryRestoreFile -Path "TestDrive:\backupsRecurse" -Recurse
        }

        AfterAll {
            Remove-Item -Path "TestDrive:\backupsRecurse" -Recurse -ErrorAction SilentlyContinue
        }

        It "Should Return an array of FileInfo" {
            $results2 | Should -BeOfType System.IO.FileSystemInfo
            $results2 | Should -BeOfType System.IO.FileSystemInfo
        }


        It "Should Return 4 files" {
            $results2.count | Should -Be 4
        }


        It "Should return 1 bak file" {
            ($results2 | Where-Object FullName -like "*\backupsRecurse\Full.bak").count | Should -Be 1
        }


        It "Should return 3 trn files" {
            ($results2 | Where-Object FullName -like "*\backupsRecurse\*.trn").count | Should -Be 3
        }

        It "Should contain log2b.trn" {
            ($results2 | Where-Object FullName -like "*\backupsRecurse\*log2b.trn").count | Should -Be 1
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $helpContent = Get-Content "$PSScriptRoot\..\private\functions\Get-DirectoryRestoreFile.ps1" -Raw
            $helpContent | Should -Match "System\.IO\.FileInfo"
        }
    }
}