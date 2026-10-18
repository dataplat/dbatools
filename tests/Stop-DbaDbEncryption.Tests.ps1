#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Stop-DbaDbEncryption",
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
}


Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbCertificate
        $db | New-DbaDbEncryptionKey -Force
        $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($db) {
            $db | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should disable encryption on a database with piping" {
            # Wait for encryption to complete before trying to disable
            $timeout = 120
            $elapsed = 0
            $encrypted = $false
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $db.Refresh()
                $dbState = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($db.Name)')"
                $encrypted = ($dbState.encryption_state -eq 3)
            } while (-not $encrypted -and $elapsed -lt $timeout)

            $results = Stop-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $false
            }
        }
    }

    Context "Parallel processing" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $parallelMastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $parallelMastercert) {
                $parallelDelmastercert = $true
                $parallelMastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
            }

            $parallelDatabases = @()
            1..3 | ForEach-Object {
                $parallelDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
                $parallelDb | New-DbaDbMasterKey -SecurePassword $passwd
                $parallelDb | New-DbaDbCertificate
                $parallelDb | New-DbaDbEncryptionKey -Force
                $parallelDb | Enable-DbaDbEncryption -EncryptorName $parallelMastercert.Name -Force
                $parallelDatabases += $parallelDb
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($parallelDatabases) {
                $parallelDatabases | Remove-DbaDatabase
            }
            if ($parallelDelmastercert) {
                $parallelMastercert | Remove-DbaDbCertificate
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "should disable encryption with -Parallel switch" {
            # Wait for encryption to complete on all databases before trying to disable
            $timeout = 120
            $elapsed = 0
            $allEncrypted = $false
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $encryptedCount = 0
                foreach ($parallelDb in $parallelDatabases) {
                    $parallelDb.Refresh()
                    $dbState = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('$($parallelDb.Name)')"
                    if ($dbState.encryption_state -eq 3) {
                        $encryptedCount++
                    }
                }
                $allEncrypted = ($encryptedCount -eq $parallelDatabases.Count)
            } while (-not $allEncrypted -and $elapsed -lt $timeout)

            $results = Stop-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Parallel -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results.Count | Should -BeGreaterOrEqual 3
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $false
            }
        }
    }

    Context "When the pipeline ends at the first database" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The contexts above decrypted every database,
            # so the command returns the first one as not encrypted, and Select-Object -First 1 stops it there.
            # The runspace imports the manifest: an import of the psm1 without a command line skips the type
            # data. It has none of the default parameter values of the tests, so Confirm is passed here.
            # The bar of -Parallel cannot be checked this way: the command runs its threads in a runspace pool
            # on $Host, and once a thread has run there, the progress records of the calling pipeline no longer
            # reach Streams.Progress.
            $splatFirstDatabase = @{
                SqlInstance = $TestConfig.InstanceSingle
                Confirm     = $false
            }
            if ($TestConfig.SqlCred) {
                $splatFirstDatabase.SqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $firstDatabase = $stopShell.AddCommand("Stop-DbaDbEncryption").AddParameters($splatFirstDatabase).AddCommand("Select-Object").AddParameter("First", 1).Invoke()
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        It "Returns a database that is not encrypted" {
            $firstDatabase.EncryptionEnabled | Should -BeFalse
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $stopRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $stopRecords | Where-Object Activity -eq "Executing Stop-DbaDbEncryption" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}