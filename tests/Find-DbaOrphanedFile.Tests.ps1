#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaOrphanedFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Orphaned files are correctly identified" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbname = "dbatoolsci_orphanedfile_$(Get-Random)"
            $dbname2 = "dbatoolsci_orphanedfile_$(Get-Random)"

            $db1 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname
            $db2 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname2

            $tmpdir = "$($TestConfig.Temp)\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir)) {
                $null = New-Item -Path $tmpdir -ItemType Directory
            }
            $tmpdirInner = Join-Path $tmpdir "inner"
            $null = New-Item -Path $tmpdirInner -ItemType Directory
            $tmpBackupPath = Join-Path $tmpdirInner "backup"
            $null = New-Item -Path $tmpBackupPath -ItemType Directory

            $tmpdir2 = "$($TestConfig.Temp)\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir2)) {
                $null = New-Item -Path $tmpdir2 -ItemType Directory
            }
            $tmpdirInner2 = Join-Path $tmpdir2 "inner"
            $null = New-Item -Path $tmpdirInner2 -ItemType Directory
            $tmpBackupPath2 = Join-Path $tmpdirInner2 "backup"
            $null = New-Item -Path $tmpBackupPath2 -ItemType Directory

            $result = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            if ($result.Count -eq 0) {
                throw "Setup failed: database not created"
            }

            $backupFile = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Path $tmpBackupPath -Type Full
            $backupFile2 = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname2 -Path $tmpBackupPath2 -Type Full

            $tmpBackupPath3 = [IO.Path]::Combine((Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle).Data, "dbatoolsci_$(Get-Random)")
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { $null = New-Item -Path $args -ItemType Directory } -ArgumentList $tmpBackupPath3

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname, $dbname2 | Remove-DbaDatabase
            Remove-Item $tmpdir -Recurse -Force
            Remove-Item $tmpdir2 -Recurse -Force
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { Remove-Item -Path $args -Recurse -Force } -ArgumentList $tmpBackupPath3

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Has the correct properties" {
            $null = Dismount-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Force
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle
            $ExpectedStdProps = "ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename".Split(",")
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedStdProps | Sort-Object)
            $ExpectedProps = "ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename,Server".Split(",")
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Finds two files" {
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle
            $results.Filename.Count | Should -Be 2
        }

        It "Finds zero files after cleaning up" {
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { Remove-Item -Path $args } -ArgumentList $results.FileName
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle
            $results.Filename.Count | Should -Be 0
        }

        It "works with -Path" {
            "a" | Out-File (Join-Path $tmpdir "out.mdf")
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -Path $tmpdir
            $results.Filename.Count | Should -Be 1

            Move-Item "$tmpdir\out.mdf" -Destination $tmpdirInner
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -Path $tmpdir
            $results.Filename.Count | Should -Be 0
        }

        It "works with -Recurse" {
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -Path $tmpdir -Recurse
            $results.Filename.Count | Should -Be 1

            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -Path $tmpdir, $tmpdir2 -Recurse -FileType bak
            $results.Filename | Should -Contain $backupFile.BackupPath
            $results.Filename | Should -Contain $backupFile2.BackupPath
            $results.Count | Should -Be 3

            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { "a" | Out-File (Join-Path $args "out.mdf") } -ArgumentList $tmpBackupPath3
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -Recurse
            $results.Filename | Should -Be "$tmpBackupPath3\out.mdf"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connection of the caller is left in the database it was in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # This command reads the directory tree through master, so a caller that is already in master
            # cannot show the leak at all. The connection starts in tempdb for that reason, and it is not
            # pooled, because a pooled connection reconnects at its default database.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database tempdb -NonPooledConnection
            $contextBefore = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $contextResult = Find-DbaOrphanedFile -SqlInstance $callerServer

            $contextAfter = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "starts in tempdb, so a leak into master can be seen at all" {
            $contextBefore | Should -Be "tempdb"
        }

        It "leaves the connection in the database it was in" {
            $contextAfter | Should -Be $contextBefore
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Logins without sysadmin and paths that need quoting (#10839)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Before SQL Server 2017 there is only xp_dirtree, which lists nothing for a login that is not sysadmin
            $supportsFileSystemDmf = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor -ge 14

            # A new login is only a member of public and sees no row in sys.master_files
            $publicLoginName = "dbatoolsci_orphan_public_$(Get-Random)"
            $publicLoginPassword = ConvertTo-SecureString -String "dbatools.IO$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $publicLoginName -SecurePassword $publicLoginPassword
            $publicLoginCredential = New-Object System.Management.Automation.PSCredential($publicLoginName, $publicLoginPassword)

            # VIEW ANY DEFINITION is enough to see every row in sys.master_files
            $viewLoginName = "dbatoolsci_orphan_view_$(Get-Random)"
            $viewLoginPassword = ConvertTo-SecureString -String "dbatools.IO$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $viewLoginName -SecurePassword $viewLoginPassword
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "GRANT VIEW ANY DEFINITION TO [$viewLoginName]"
            $viewLoginCredential = New-Object System.Management.Automation.PSCredential($viewLoginName, $viewLoginPassword)

            # The instance lists these folders, so they go to the temp folder that the instance can reach.
            # The name of the Unicode folder is built from code points, because Windows PowerShell reads a test
            # file without byte order mark in the ANSI code page.
            $treePath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $quoteFolder = "$treePath\dbatoolsci_O'Brien"
            $unicodeFolder = "$treePath\dbatoolsci_M$([char]0x00FC)ller_$([char]0x65E5)$([char]0x672C)"
            $recurseFolder = "$treePath\dbatoolsci_recurse"
            $null = New-Item -Path $quoteFolder, $unicodeFolder, $recurseFolder -ItemType Directory
            $orphanFiles = @(
                "$treePath\dbatoolsci_orphan.mdf",
                "$quoteFolder\dbatoolsci_orphan.ndf",
                "$unicodeFolder\dbatoolsci_orphan.ldf",
                "$recurseFolder\dbatoolsci_orphan.mdf"
            )
            foreach ($orphanFile in $orphanFiles) {
                Set-Content -LiteralPath $orphanFile -Value "dbatoolsci"
            }

            # A folder created on a share can stay invisible to the instance for some seconds
            $visibleBefore = (Get-Date).AddSeconds(60)
            while (-not (Test-DbaPath -SqlInstance $TestConfig.InstanceSingle -Path "$recurseFolder\dbatoolsci_orphan.mdf") -and (Get-Date) -lt $visibleBefore) {
                Start-Sleep -Seconds 2
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Force, in case a test failed before it closed the connection of its login
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $publicLoginName, $viewLoginName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $treePath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Refuses a login that cannot see the files of the databases" {
            # Without a row in sys.master_files every file on disk would count as orphaned. The command ended with an exception instead.
            # The test opens the connection of the login itself and closes it, so that no pooled session blocks dropping the login.
            $publicServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $publicLoginCredential -NonPooledConnection
            $results = Find-DbaOrphanedFile -SqlInstance $publicServer -Path $treePath -WarningAction SilentlyContinue
            # Disconnect-DbaInstance sets the warning variable as well
            $findWarnings = $WarnVar
            $null = $publicServer | Disconnect-DbaInstance
            $results | Should -BeNullOrEmpty
            $findWarnings | Should -BeLike "*Cannot read the database files*"
        }

        It "Finds orphaned files for a login that sees the files of the databases without being sysadmin" {
            if (-not $supportsFileSystemDmf) {
                Set-ItResult -Skipped -Because "xp_dirtree lists nothing for a login that is not sysadmin before SQL Server 2017"
            }
            # xp_dirtree returned no row for such a login, so no orphaned file was ever found
            $viewServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $viewLoginCredential -NonPooledConnection
            $results = Find-DbaOrphanedFile -SqlInstance $viewServer -Path $treePath
            $findWarnings = $WarnVar
            $null = $viewServer | Disconnect-DbaInstance
            $results.Filename | Where-Object { $PSItem -like "$treePath\*" } | Should -Be "$treePath\dbatoolsci_orphan.mdf"
            $findWarnings | Should -BeNullOrEmpty
        }

        It "Finds orphaned files in folders whose names need quoting" {
            # The path went into the query without quoting and without N, so a quote broke the batch, a character outside the
            # code page of the instance pointed to a folder that does not exist, and "recurse" became the depth of xp_dirtree
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -Path $quoteFolder, $unicodeFolder, $recurseFolder
            $foundFiles = $results.Filename | Where-Object { $PSItem -like "$treePath\*" }
            $expectedFiles = $orphanFiles | Where-Object { $PSItem -notlike "$treePath\dbatoolsci_orphan.*" }
            Compare-Object -ReferenceObject $expectedFiles -DifferenceObject @($foundFiles) | Should -BeNullOrEmpty
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Warns instead of ending with an exception when the query fails" {
            # Every level of the system drive takes longer than a statement timeout of one second
            $timeoutServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -StatementTimeout 1
            $driveRoot = $timeoutServer.RootDirectory.Substring(0, 3)
            $results = Find-DbaOrphanedFile -SqlInstance $timeoutServer -Path $driveRoot -Recurse -WarningAction SilentlyContinue
            $timeoutServer.ConnectionContext.Disconnect()
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -BeLike "*Failure listing the directories*"
        }
    }
}
