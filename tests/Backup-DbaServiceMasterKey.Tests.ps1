#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaServiceMasterKey",
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
                "KeyCredential",
                "SecurePassword",
                "Path",
                "FileBaseName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Can backup a service master key" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        }

        AfterAll {
            # Clean up any remaining files that weren't in the backup directory
            if ($smkBackupPath) {
                Remove-Item -Path $smkBackupPath -ErrorAction SilentlyContinue
            }
            if ($fileBackupPath) {
                Remove-Item -Path $fileBackupPath -ErrorAction SilentlyContinue
            }
        }

        It "backs up the SMK" {
            $splatBackup = @{
                SqlInstance    = $TestConfig.InstanceSingle
                SecurePassword = $securePassword
                Path           = $backupPath
            }
            $backupResults = Backup-DbaServiceMasterKey @splatBackup
            $backupResults.Status | Should -Be "Success"
            $smkBackupPath = $backupResults.Path
        }

        It "backs up the SMK with a specific filename (see #9483)" {
            $randomNum = Get-Random
            $splatFileBackup = @{
                SqlInstance    = $TestConfig.InstanceSingle
                SecurePassword = $securePassword
                Path           = $backupPath
                FileBaseName   = "smk($randomNum)"
            }
            $fileBackupResults = Backup-DbaServiceMasterKey @splatFileBackup
            [IO.Path]::GetFileNameWithoutExtension($fileBackupResults.Path) | Should -Be "smk($randomNum)"
            $fileBackupResults.Status | Should -Be "Success"
            $fileBackupPath = $fileBackupResults.Path
        }

        It "prompts once for the run, matching the source function's two-call lifetime over two records" {
            $promptServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $promptPath = $promptServer.BackupDirectory
            $promptFileBaseName = "smkpromptcarry_$(Get-Random)"
            $splatPromptPath = @{
                SqlInstance = $promptServer
                Path        = $promptPath
                ChildPath   = "$promptFileBaseName.key"
            }
            $promptExpectedFile = Join-DbaPath @splatPromptPath
            Test-DbaPath -SqlInstance $promptServer -Path $promptExpectedFile | Should -BeFalse

            # The mock body runs inside the dbatools module scope, so it builds its own SecureString
            # rather than closing over $securePassword, which does not resolve there under Pester 5.
            Mock Read-Host -ModuleName dbatools { ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force }
            $splatPromptCarry = @{
                Path         = $promptPath
                FileBaseName = $promptFileBaseName
                WhatIf       = $true
            }
            @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle) | Backup-DbaServiceMasterKey @splatPromptCarry

            Should -Invoke Read-Host -ModuleName dbatools -Times 2 -Exactly
            Test-DbaPath -SqlInstance $promptServer -Path $promptExpectedFile | Should -BeFalse
        }
    }
}