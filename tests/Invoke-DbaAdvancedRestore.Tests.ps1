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
                Mock Connect-DbaInstance { $script:mockServer }
                Mock New-Object {
                    $script:lastRestore = New-MockRestore
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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $singleBackupPath = "$($TestConfig.AppveyorLabRepo)\singlerestore\singlerestore.bak"
        $restoredDbName = "dbatoolsci_advrestore_$(Get-Random)"

        # The fixture's embedded file paths point at the 2008 R2 default data directory of
        # the box that took the backup, so retarget them at this instance's defaults and a
        # unique database name before handing the chain to Invoke-DbaAdvancedRestore.
        $defaultPath = Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle
        $splatFormat = @{
            DataFileDirectory   = $defaultPath.Data
            LogFileDirectory    = $defaultPath.Log
            ReplaceDatabaseName = $restoredDbName
            ReplaceDbNameInFile = $true
        }
        $backupHistory = Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -Path $singleBackupPath | Format-DbaBackupInformation @splatFormat | Select-DbaBackupInformation

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $restoredDbName -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Scripting a restore" {
        It "Returns the restore T-SQL with -OutputScriptOnly" {
            $scriptOnly = $backupHistory | Invoke-DbaAdvancedRestore -SqlInstance $TestConfig.InstanceSingle -OutputScriptOnly -WithReplace
            $scriptOnly | Should -BeOfType [System.String]
            $scriptOnly | Should -Match "RESTORE DATABASE \[$restoredDbName\]"
        }
    }

    Context "Running a restore" {
        It "Restores the database from piped backup history" {
            $restoreResults = $backupHistory | Invoke-DbaAdvancedRestore -SqlInstance $TestConfig.InstanceSingle -WithReplace
            @($restoreResults).Count | Should -BeExactly 1
            $restoreResults.RestoreComplete | Should -BeTrue
            $restoreResults.Database | Should -Be $restoredDbName
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $restoredDbName).Name | Should -Be $restoredDbName
        }
    }

    Context "VerifyOnly" {
        It "Emits the verify message and the result object" {
            $verifyResults = @($backupHistory | Invoke-DbaAdvancedRestore -SqlInstance $TestConfig.InstanceSingle -VerifyOnly)
            # characterization: current behavior emits BOTH the literal string and the
            # result object for a successful VerifyOnly run, do not "fix" without a
            # surface-diff decision
            $verifyResults.Count | Should -BeExactly 2
            $verifyResults[0] | Should -Be "Verify successful"
            $verifyResults[1].RestoreComplete | Should -BeTrue
        }
    }
}