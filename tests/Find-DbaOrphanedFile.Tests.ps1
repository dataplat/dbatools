param($ModuleName = 'dbatools')

Describe "Find-DbaOrphanedFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaOrphanedFile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[]
        }
        It "Should have FileType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileType -Type String[]
        }
        It "Should have LocalOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter LocalOnly -Type Switch
        }
        It "Should have RemoteOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter RemoteOnly -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have Recurse as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Recurse -Type Switch
        }
    }

    Context "Orphaned files are correctly identified" {
        BeforeAll {
            $dbname = "dbatoolsci_orphanedfile_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db1 = New-DbaDatabase -SqlInstance $server -Name $dbname

            $dbname2 = "dbatoolsci_orphanedfile_$(Get-Random)"
            $db2 = New-DbaDatabase -SqlInstance $server -Name $dbname2

            $tmpdir = "c:\temp\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir)) {
                $null = New-Item -Path $tmpdir -type Container
            }
            $tmpdirInner = Join-Path $tmpdir "inner"
            $null = New-Item -Path $tmpdirInner -type Container
            $tmpBackupPath = Join-Path $tmpdirInner "backup"
            $null = New-Item -Path $tmpBackupPath -type Container

            $tmpdir2 = "c:\temp\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir2)) {
                $null = New-Item -Path $tmpdir2 -type Container
            }
            $tmpdirInner2 = Join-Path $tmpdir2 "inner"
            $null = New-Item -Path $tmpdirInner2 -type Container
            $tmpBackupPath2 = Join-Path $tmpdirInner2 "backup"
            $null = New-Item -Path $tmpBackupPath2 -type Container

            $result = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname
            if ($result.count -eq 0) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }

            $backupFile = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Path $tmpBackupPath -Type Full
            $backupFile2 = Backup-DbaDatabase -SqlInstance $global:instance2 -Database $dbname2 -Path $tmpBackupPath2 -Type Full
            Copy-Item -Path $backupFile.BackupPath -Destination "C:\" -Confirm:$false

            $tmpBackupPath3 = Join-Path (Get-SqlDefaultPaths $server data) "dbatoolsci_$(Get-Random)"
            $null = New-Item -Path $tmpBackupPath3 -type Container
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname, $dbname2 | Remove-DbaDatabase -Confirm:$false
            Remove-Item $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpdir2 -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "C:\$($backupFile.BackupFile)" -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpBackupPath3 -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Has the correct properties" {
            $null = Detach-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Force
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2
            $ExpectedStdProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename'.Split(',')
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedStdProps | Sort-Object)
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename,Server'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Finds two files" {
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2
            $results.Filename.Count | Should -Be 2
        }

        It "Finds zero files after cleaning up" {
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2
            $results.FileName | Remove-Item
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2
            $results.Filename.Count | Should -Be 0
        }

        It "works with -Recurse" {
            "a" | Out-File (Join-Path $tmpdir "out.mdf")
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2 -Path $tmpdir
            $results.Filename.Count | Should -Be 1
            Move-Item "$tmpdir\out.mdf" -destination $tmpdirInner
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2 -Path $tmpdir
            $results.Filename.Count | Should -Be 0
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2 -Path $tmpdir -Recurse
            $results.Filename.Count | Should -Be 1

            Copy-Item -Path "$tmpdirInner\out.mdf" -Destination $tmpBackupPath3 -Confirm:$false

            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2 -Path $tmpdir, $tmpdir2 -Recurse -FileType bak
            $results.Filename | Should -Contain $backupFile.BackupPath
            $results.Filename | Should -Contain $backupFile2.BackupPath
            $results.Filename | Should -Contain "$tmpdirInner\out.mdf"
            $results.Filename | Should -Contain "$tmpBackupPath3\out.mdf"
            $results.Count | Should -Be 4

            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2 -Recurse
            $results.Filename | Should -Be "$tmpBackupPath3\out.mdf"
        }

        It "works with -Path" {
            $results = Find-DbaOrphanedFile -SqlInstance $global:instance2 -Path "C:" -FileType bak
            $results.Filename | Should -Contain "C:\$($backupFile.BackupFile)"
        }
    }
}
