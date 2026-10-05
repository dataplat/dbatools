#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Start-DbaDbEncryption",
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
                "EncryptorName",
                "EncryptorType",
                "Database",
                "ExcludeDatabase",
                "BackupPath",
                "MasterKeySecurePassword",
                "CertificateSubject",
                "CertificateStartDate",
                "CertificateExpirationDate",
                "CertificateActiveForServiceBrokerDialog",
                "BackupSecurePassword",
                "InputObject",
                "AllUserDatabases",
                "Force",
                "Parallel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Parallel cleanup" {
        It "disconnects thread-local connections even during WhatIf execution" {
            $commandAst = (Get-Command $CommandName).ScriptBlock.Ast
            $disconnectCommands = $commandAst.FindAll( {
                    param($Ast)

                    $Ast -is [System.Management.Automation.Language.CommandAst] -and
                    $Ast.GetCommandName() -eq "Disconnect-DbaInstance"
                }, $true)

            $disconnectCommands.Count | Should -Be 1

            $expectedArgument = "-WhatIf:" + [char]36 + "false"
            $disconnectCommands[0].Extent.Text | Should -Match ([regex]::Escape($expectedArgument))
        }
    }

    Context "Parallel exclusions" {
        It "uses the filtered database list when pre-creating encryption keys" {
            $commandText = (Get-Command $CommandName).ScriptBlock.Ast.Extent.Text
            $parallelBlockStart = $commandText.IndexOf("# Step 3: Create a database encryption key in the target database if needed")
            $parallelBlockLength = [Math]::Min(500, $commandText.Length - $parallelBlockStart)
            $parallelBlockText = $commandText.Substring($parallelBlockStart, $parallelBlockLength)
            $expectedText = "foreach (" + [char]36 + "db in " + [char]36 + "databases)"

            $parallelBlockText | Should -Match ([regex]::Escape($expectedText))
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test database encryption, we need multiple test databases.

        # Set variables. They are available in all the It blocks.
        $testDatabases = @()
        1..5 | ForEach-Object {
            $testDatabases += New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        if ($testDatabases) {
            $testDatabases | Remove-DbaDatabase
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should mass enable encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splatEncryption = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $testDatabases.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $backupPath
            }
            $results = Start-DbaDbEncryption @splatEncryption
            $WarnVar | Should -BeNullOrEmpty
            $results.Count | Should -Be 5
            $results | Select-Object -First 1 -ExpandProperty EncryptionEnabled | Should -Be $true
            $results | Select-Object -First 1 -ExpandProperty DatabaseName | Should -Match "random"
        }
    }

    Context "Parallel processing" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $parallelBackupPath = "$($TestConfig.Temp)\$CommandName-Parallel-$(Get-Random)"
            $null = New-Item -Path $parallelBackupPath -ItemType Directory

            $parallelTestDatabases = @()
            1..3 | ForEach-Object {
                $parallelTestDatabases += New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($parallelTestDatabases) {
                $parallelTestDatabases | Remove-DbaDatabase
            }

            Remove-Item -Path $parallelBackupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "should enable encryption with -Parallel switch" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splatParallelEncryption = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $parallelTestDatabases.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $parallelBackupPath
                Parallel                = $true
            }
            # Warnings during parallel execution are not catched in $WarnVar as they are in different runspaces
            $results = Start-DbaDbEncryption @splatParallelEncryption
            $WarnVar | Should -BeNullOrEmpty
            $results.Count | Should -Be 3
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $true
            }
            $results.DatabaseName | Should -Contain $parallelTestDatabases[0].Name
        }
    }

    Context "When the pipeline ends early" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $firstOnlyDatabases = @()
            1..2 | ForEach-Object {
                $firstOnlyDatabases += New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The runspace imports the manifest: an import
            # of the psm1 without a command line skips the type data.
            # The bar of -Parallel cannot be checked this way: the command runs its threads in a runspace pool
            # on $Host, and once a thread has run there, the progress records of the calling pipeline no longer
            # reach Streams.Progress.
            $earlyPassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $earlyRunspace = [runspacefactory]::CreateRunspace()
            $earlyRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $earlyRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            # Select-Object -First 1 stops the command as soon as the first database is encrypted. The runspace
            # has none of the default parameter values of the tests, so Confirm is passed here.
            $splatFirstOnly = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $firstOnlyDatabases.Name
                MasterKeySecurePassword = $earlyPassword
                BackupSecurePassword    = $earlyPassword
                BackupPath              = $backupPath
                Confirm                 = $false
            }
            if ($TestConfig.SqlCred) {
                $splatFirstOnly.SqlCredential = $TestConfig.SqlCred
            }
            $firstOnlyShell = [powershell]::Create()
            $firstOnlyShell.Runspace = $earlyRunspace
            $firstOnlyResult = $firstOnlyShell.AddCommand("Start-DbaDbEncryption").AddParameters($splatFirstOnly).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
            $firstOnlyRecords = @($firstOnlyShell.Streams.Progress)
            $firstOnlyShell.Dispose()
            $earlyRunspace.Dispose()
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $firstOnlyDatabases.Name
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Stops after the first database" {
            $firstOnlyResult.Count | Should -Be 1
            $encryptedDatabases = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $firstOnlyDatabases.Name | Where-Object EncryptionEnabled
            @($encryptedDatabases).Count | Should -Be 1
        }

        It "Completes its progress bar when the pipeline ends early" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $firstOnlyRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $firstOnlyRecords | Where-Object Activity -eq "Executing Start-DbaDbEncryption" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }

}