#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaBackupHeader",
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
                "Simple",
                "FileList",
                "StorageCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When Path is a folder" {
        It "Warns that it needs a file and returns nothing" {
            # The message used to be built from a broken string literal, "Path ("$p") should be a file, not a folder",
            # which handed $p to Stop-Function as a positional argument and turned the warning into a binding error.
            $splatFolder = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Path          = $TestConfig.Temp
                WarningAction = "SilentlyContinue"
            }
            $results = Read-DbaBackupHeader @splatFolder
            $results | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -BeLike "*should be a file, not a folder*"
        }
    }

    Context "When it runs in a host created by the PowerShell API" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $apiPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $apiPath -ItemType Directory
            # The instance can open this file, but it holds no backup, so the thread that reads it fails.
            $noBackupFile = "$apiPath\nobackup.bak"
            Set-Content -Path $noBackupFile -Value "This is no backup."
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The command runs in a runspace of its own, created by the PowerShell API without a host, as automation
            # and SDK hosts do. Its threads used to run in a runspace pool on $Host, and once a thread had run there,
            # the warnings and progress records of the calling pipeline no longer reached the streams of that host.
            # The warning about the failed thread is written after the thread has run. The runspace imports the
            # manifest: an import of the psm1 without a command line skips the type data.
            $apiRunspace = [runspacefactory]::CreateRunspace()
            $apiRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $apiRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $splatNoBackup = @{
                SqlInstance = $TestConfig.InstanceSingle
                Path        = $noBackupFile
            }
            if ($TestConfig.SqlCred) {
                $splatNoBackup.SqlCredential = $TestConfig.SqlCred
            }
            $apiShell = [powershell]::Create()
            $apiShell.Runspace = $apiRunspace
            $apiResult = $apiShell.AddCommand($CommandName).AddParameters($splatNoBackup).Invoke()
            $apiWarnings = @($apiShell.Streams.Warning)
            $apiRecords = @($apiShell.Streams.Progress)
            $apiShell.Dispose()
            $apiRunspace.Dispose()
        }

        AfterAll {
            Remove-Item -Path $apiPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns nothing for the file without a backup" {
            $apiResult | Should -BeNullOrEmpty
        }

        It "Writes its warning to the streams of the host" {
            ($apiWarnings.Message -join " ") | Should -BeLike "*Problem found with*nobackup.bak*"
        }

        It "Writes the completion of its progress bar to the streams of the host" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so the completed record of Id 1 is asserted by itself.
            $openIds = $apiRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $apiRecords | Where-Object { $PSItem.ActivityId -eq 1 -and $PSItem.RecordType -eq "Completed" } | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }

    Context "When the pipeline ends early" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $earlyPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $earlyPath -ItemType Directory
            $earlyDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $splatEarlyBackup = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $earlyDb.Name
                Path        = $earlyPath
            }
            $earlyBackup = Backup-DbaDatabase @splatEarlyBackup
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $earlyDb.Name
            Remove-Item -Path $earlyPath -Recurse -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Closes its runspace pool" {
            # Select-Object -First 1 stops the command at the first header it returns, while the loop that receives
            # the threads still runs. The pool used to be closed only after that loop, so its runspace stayed open.
            $openBefore = @(Get-Runspace | Where-Object { $PSItem.RunspaceStateInfo.State -eq "Opened" }).Count
            $firstHeader = Read-DbaBackupHeader -SqlInstance $TestConfig.InstanceSingle -Path $earlyBackup.BackupPath | Select-Object -First 1
            $openAfter = @(Get-Runspace | Where-Object { $PSItem.RunspaceStateInfo.State -eq "Opened" }).Count
            $firstHeader.DatabaseName | Should -Be $earlyDb.Name
            $openAfter | Should -Be $openBefore
        }
    }
}
