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
            $results = Find-DbaOrphanedFile -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Server",
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Filename",
                "RemoteFilename"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Filename",
                "RemoteFilename"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}