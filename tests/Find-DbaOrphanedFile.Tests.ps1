#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaOrphanedFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "FileType",
                "LocalOnly",
                "RemoteOnly",
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
    Context "Orphaned files are correctly identified" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $dbname = "dbatoolsci_orphanedfile_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $db1 = New-DbaDatabase -SqlInstance $server -Name $dbname

            $dbname2 = "dbatoolsci_orphanedfile_$(Get-Random)"
            $db2 = New-DbaDatabase -SqlInstance $server -Name $dbname2

            $tmpdir = "c:\temp\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir)) {
                $null = New-Item -Path $tmpdir -ItemType Directory
            }
            $tmpdirInner = Join-Path $tmpdir "inner"
            $null = New-Item -Path $tmpdirInner -ItemType Directory
            $tmpBackupPath = Join-Path $tmpdirInner "backup"
            $null = New-Item -Path $tmpBackupPath -ItemType Directory

            $tmpdir2 = "c:\temp\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir2)) {
                $null = New-Item -Path $tmpdir2 -ItemType Directory
            }
            $tmpdirInner2 = Join-Path $tmpdir2 "inner"
            $null = New-Item -Path $tmpdirInner2 -ItemType Directory
            $tmpBackupPath2 = Join-Path $tmpdirInner2 "backup"
            $null = New-Item -Path $tmpBackupPath2 -ItemType Directory

            $result = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname
            if ($result.Count -eq 0) {
                throw "Setup failed: database not created"
            }

            $backupFile = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Path $tmpBackupPath -Type Full
            $backupFile2 = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname2 -Path $tmpBackupPath2 -Type Full
            Copy-Item -Path $backupFile.BackupPath -Destination "C:\" -Confirm:$false

            $tmpBackupPath3 = Join-Path (Get-SqlDefaultPaths $server data) "dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $tmpBackupPath3 -ItemType Directory

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname, $dbname2 | Remove-DbaDatabase -Confirm:$false
            Remove-Item $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpdir2 -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "C:\$($backupFile.BackupFile)" -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpBackupPath3 -Recurse -Force -ErrorAction SilentlyContinue

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }
        It "Has the correct properties" {
            $null = Dismount-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Force
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2
            $ExpectedStdProps = "ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename".Split(",")
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedStdProps | Sort-Object)
            $ExpectedProps = "ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename,Server".Split(",")
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }


        It "Finds two files" {
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2
            $results.Filename.Count | Should -Be 2
        }

        It "Finds zero files after cleaning up" {
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2
            $results.FileName | Remove-Item
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2
            $results.Filename.Count | Should -Be 0
        }
        It "works with -Recurse" {
            "a" | Out-File (Join-Path $tmpdir "out.mdf")
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2 -Path $tmpdir
            $results.Filename.Count | Should -Be 1
            Move-Item "$tmpdir\out.mdf" -Destination $tmpdirInner
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2 -Path $tmpdir
            $results.Filename.Count | Should -Be 0
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2 -Path $tmpdir -Recurse
            $results.Filename.Count | Should -Be 1

            Copy-Item -Path "$tmpdirInner\out.mdf" -Destination $tmpBackupPath3 -Confirm:$false

            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2 -Path $tmpdir, $tmpdir2 -Recurse -FileType bak
            $results.Filename | Should -Contain $backupFile.BackupPath
            $results.Filename | Should -Contain $backupFile2.BackupPath
            $results.Filename | Should -Contain "$tmpdirInner\out.mdf"
            $results.Filename | Should -Contain "$tmpBackupPath3\out.mdf"
            $results.Count | Should -Be 4

            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2 -Recurse
            $results.Filename | Should -Be "$tmpBackupPath3\out.mdf"
        }
        It "works with -Path" {
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.instance2 -Path "C:" -FileType bak
            $results.Filename | Should -Contain "C:\$($backupFile.BackupFile)"
        }
    }
}