#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaAdvancedRestore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "BackupHistory",
                "SqlInstance",
                "SqlCredential",
                "OutputScriptOnly",
                "VerifyOnly",
                "RestoreTime",
                "StandbyDirectory",
                "NoRecovery",
                "MaxTransferSize",
                "BlockSize",
                "BufferCount",
                "Continue",
                "StorageCredential",
                "WithReplace",
                "KeepReplication",
                "KeepCDC",
                "ErrorBrokerConversations",
                "PageRestore",
                "ExecuteAs",
                "StopBefore",
                "StopMark",
                "StopAfterDate",
                "Checksum",
                "Restart",
                "StopAtLsn",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "ErrorBrokerConversations behavior" {
            BeforeAll {
                function Add-TeppCacheItem { }
                function New-MockRestore {
                    $restore = [PSCustomObject]@{
                        NoRecovery              = $false
                        StandbyFile             = $null
                        Database                = $null
                        ReplaceDatabase         = $false
                        MaxTransferSize         = $null
                        BufferCount             = $null
                        Blocksize               = $null
                        Checksum                = $false
                        Restart                 = $false
                        KeepReplication         = $false
                        Action                  = $null
                        FileNumber              = $null
                        ToPointInTime           = $null
                        StopBeforeMarkName      = $null
                        StopAtMarkName          = $null
                        StopBeforeMarkAfterDate = $null
                        StopAtMarkAfterDate     = $null
                        RelocateFiles           = (New-Object System.Collections.ArrayList)
                        Devices                 = (New-Object System.Collections.ArrayList)
                    }
                    Add-Member -InputObject $restore -Name Script -MemberType ScriptMethod -Value {
                        param($Server)
                        "RESTORE DATABASE [$($this.Database)] FROM DISK = 'C:\backups\test.bak' WITH REPLACE"
                    } -Force
                    $restore
                }

                $script:mockServer = [PSCustomObject]@{
                    Databases             = @()
                    DatabaseEngineEdition = "SqlServer"
                    ConnectionContext     = [PSCustomObject]@{
                        TrueLogin = "dbatoolsci"
                        exists    = $false
                    }
                }
                Add-Member -InputObject $script:mockServer.ConnectionContext -Name ExecuteNonQuery -MemberType ScriptMethod -Value {
                    param($Query)
                    $null
                } -Force
                Add-Member -InputObject $script:mockServer.ConnectionContext -Name Disconnect -MemberType ScriptMethod -Value { } -Force

                $script:backupHistory = [PSCustomObject]@{
                    Database      = "RestoreAsDb"
                    Type          = "1"
                    FirstLsn      = 1
                    RestoreTime   = (Get-Date).AddMinutes(-5)
                    RecoveryModel = "Full"
                    FileList      = @(
                        [PSCustomObject]@{
                            LogicalName  = "RestoreAsDb"
                            PhysicalName = "C:\restore\RestoreAsDb.mdf"
                        }
                    )
                    FullName      = @("C:\backups\RestoreAsDb.bak")
                    Position      = 1
                }

                function Test-FunctionInterrupt { $false }
                function Write-Message { }
            }

            BeforeEach {
                $script:mockRestores = @()
                Mock Connect-DbaInstance { $script:mockServer }
                Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters }
                Mock New-Object {
                    $script:lastRestore = New-MockRestore
                    $script:mockRestores += $script:lastRestore
                    $script:lastRestore
                } -ParameterFilter {
                    $TypeName -eq "Microsoft.SqlServer.Management.Smo.Restore"
                }
                Mock New-Object {
                    [PSCustomObject]@{
                        LogicalFileName  = $null
                        PhysicalFileName = $null
                    }
                } -ParameterFilter {
                    $TypeName -eq "Microsoft.SqlServer.Management.Smo.RelocateFile"
                }
                Mock New-Object {
                    [PSCustomObject]@{
                        Name       = $null
                        devicetype = $null
                    }
                } -ParameterFilter {
                    $TypeName -eq "Microsoft.SqlServer.Management.Smo.BackupDeviceItem"
                }
            }

            It "Should call Stop-Function when ErrorBrokerConversations is combined with NoRecovery" {
                Mock Stop-Function {
                    throw $Message
                }

                { Invoke-DbaAdvancedRestore -BackupHistory $script:backupHistory -SqlInstance "sql1" -NoRecovery -ErrorBrokerConversations } | Should -Throw "*ErrorBrokerConversations cannot be specified with Norecovery or Standby as it needs recovery to work*"
            }

            It "Should prefix OutputScriptOnly with Execute As when ErrorBrokerConversations is specified" {
                Mock Stop-Function { }
                $output = Invoke-DbaAdvancedRestore -BackupHistory $script:backupHistory -SqlInstance "sql1" -OutputScriptOnly -ErrorBrokerConversations -ExecuteAs "RestoreAs"
                $scriptOutput = $output | Select-Object -Last 1

                $scriptOutput | Should -BeLike "EXECUTE AS LOGIN='RestoreAs'*ERROR_BROKER_CONVERSATIONS*"
                Should -Invoke Stop-Function -Times 0
            }

            It "Should convert fn_dblog-style StopAtLsn values before scripting the restore" {
                Mock Stop-Function { }
                $null = Invoke-DbaAdvancedRestore -BackupHistory $script:backupHistory -SqlInstance "sql1" -OutputScriptOnly -StopAtLsn "00000014:000000f3:0001"

                $script:lastRestore.StopAtMarkName | Should -Be "lsn:20000000024300001"
                $script:lastRestore.StopBeforeMarkName | Should -BeNullOrEmpty
                Should -Invoke Stop-Function -Times 0
            }

            It "Should respect StopBefore when StopAtLsn already includes the SQL lsn prefix" {
                Mock Stop-Function { }
                $null = Invoke-DbaAdvancedRestore -BackupHistory $script:backupHistory -SqlInstance "sql1" -OutputScriptOnly -StopAtLsn "lsn:20000000024300001" -StopBefore

                $script:lastRestore.StopBeforeMarkName | Should -Be "lsn:20000000024300001"
                $script:lastRestore.StopAtMarkName | Should -BeNullOrEmpty
                Should -Invoke Stop-Function -Times 0
            }

            It "Should reject invalid StopAtLsn values" {
                Mock Stop-Function {
                    throw $Message
                }

                { Invoke-DbaAdvancedRestore -BackupHistory $script:backupHistory -SqlInstance "sql1" -OutputScriptOnly -StopAtLsn "bad-lsn" } | Should -Throw "*StopAtLsn must be a numeric restore LSN or a colon-delimited value*"
            }

        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # A full and a log backup, so that the restore runs more than one backup file. The disconnect this is
        # about sat inside the loop over the backup files, so a single file would not show the whole of it.
        $restoreDbName = "dbatoolsci_advrestore_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $restoreDbName -RecoveryModel Full
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $restoreDbName -BackupDirectory $backupPath -Type Full
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $restoreDbName -BackupDirectory $backupPath -Type Log

        # The history is what Restore-DbaDatabase builds before it hands over, so the tests below can call the
        # command the same way it does.
        $backupHistory = Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -Path $backupPath |
            Select-DbaBackupInformation |
            Format-DbaBackupInformation |
            Test-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -WithReplace

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $restoreDbName -ErrorAction SilentlyContinue
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "The connection of the caller is left alone (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only a non-pooled connection can show this. SMO silently reopens a pooled connection, so the test
            # would pass even with the disconnect after every backup file.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $splatRestore = @{
                SqlInstance = $callerServer
                WithReplace = $true
            }
            $callerResult = $backupHistory | Invoke-DbaAdvancedRestore @splatRestore

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores every backup file" {
            $callerResult.Count | Should -BeGreaterThan 1
            $callerResult.RestoreComplete | Should -Not -Contain $false
        }

        It "leaves the connection open" {
            $callerServer.ConnectionContext.IsOpen | Should -BeTrue
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }

        It "leaves the connection in the database it was on" {
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }
    }

    Context "The connection of the caller of Restore-DbaDatabase is left alone (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Restore-DbaDatabase connects once and hands that server object down, so this is the connection that
            # gets closed in practice.
            $restoreCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $restoreCallerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $splatRestoreDatabase = @{
                SqlInstance = $restoreCallerServer
                Path        = $backupPath
                WithReplace = $true
            }
            $restoreCallerResult = Restore-DbaDatabase @splatRestoreDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $restoreCallerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores every backup file" {
            $restoreCallerResult.RestoreComplete | Should -Not -Contain $false
        }

        It "leaves the connection open, so the session survives" {
            { $restoreCallerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }

    Context "The command still closes the connection it opens itself" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Passing the name instead of a server object is the other side of the guard: the command opens the
            # connection here, so it is the one that has to close it again.
            $splatRestoreByName = @{
                SqlInstance = $TestConfig.InstanceSingle
                WithReplace = $true
            }
            $ownResult = $backupHistory | Invoke-DbaAdvancedRestore @splatRestoreByName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores every backup file" {
            $ownResult.RestoreComplete | Should -Not -Contain $false
        }

        It "does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}
