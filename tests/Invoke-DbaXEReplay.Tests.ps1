#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaXEReplay",
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
                "Database",
                "Event",
                "InputObject",
                "Raw",
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
Describe $CommandName -Tag IntegrationTests -Skip:(-not (Get-Command -Name sqlcmd -ErrorAction Ignore)) {
    Context "When replaying into a database context" {
        It "Runs the batch in the requested database" {
            # -Database was declared and documented but never handed to sqlcmd, so every replay ran in the default
            # database of the login (#10607).
            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "SELECT DB_NAME() AS dbatoolsci_replay_db"
            }
            $results = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            ($results -join " ") | Should -BeLike "*tempdb*"
        }
    }

    Context "Replaying the events it is given" {
        BeforeAll {
            # An event that is not in -Event is skipped, and the events after it are still replayed. The replay runs in a
            # loop of its own, so a skip that leaves the command instead of the event shows as a round that never completed.
            $events = @(
                [PSCustomObject]@{
                    Name      = "rpc_completed"
                    statement = "SELECT 1 AS dbatoolsci_replay_rpc"
                }
                [PSCustomObject]@{
                    Name       = "error_reported"
                    batch_text = "SELECT 1 AS dbatoolsci_replay_skipped"
                }
                [PSCustomObject]@{
                    Name       = "sql_batch_completed"
                    batch_text = "SELECT 1 AS dbatoolsci_replay_batch"
                }
            )
            $roundsCompleted = 0
            foreach ($round in 1..1) {
                $results = $events | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle
                $roundsCompleted++
            }
        }

        It "completes the pipeline of the caller" {
            $roundsCompleted | Should -Be 1
        }

        It "replays rpc_completed events by default" {
            ($results -join " ") | Should -BeLike "*dbatoolsci_replay_rpc*"
        }

        It "replays the events after one that is not in -Event" {
            ($results -join " ") | Should -BeLike "*dbatoolsci_replay_batch*"
        }

        It "does not replay an event that is not in -Event" {
            ($results -join " ") | Should -Not -BeLike "*dbatoolsci_replay_skipped*"
        }
    }

    Context "Filtering the output of sqlcmd" {
        BeforeAll {
            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "SELECT 1 AS dbatoolsci_first, 2 AS dbatoolsci_second"
            }
            $results = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle
        }

        It "keeps the column headers" {
            ($results -join " ") | Should -BeLike "*dbatoolsci_first*dbatoolsci_second*"
        }

        It "leaves out the dashes that underline the column headers" {
            $results | Where-Object { $PSItem -match "^[-\s]+$" } | Should -BeNullOrEmpty
        }
    }

    Context "Replaying statements with characters outside ASCII" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Every sqlcmd has to read the replay file as it was written, in both editions of PowerShell. The name of a
            # table carries the characters, so they are read back on the server and not from the console output of
            # sqlcmd. They are built from their code points, so the encoding of this test file plays no part.
            $tablePrefix = "dbatoolsci_replay_$(Get-Random)_"
            $tableName = $tablePrefix + [char]0x00E4 + [char]0x00F6 + [char]0x00FC + [char]0x20AC + [char]0x6F22 + [char]0x5B57
            $lookupParameter = @{
                prefix = "$tablePrefix%"
            }
            $splatTableLookup = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Database     = "tempdb"
                Query        = "SELECT name FROM sys.tables WHERE name LIKE @prefix"
                SqlParameter = $lookupParameter
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "CREATE TABLE tempdb.dbo.[$tableName] (Id int);"
            }
            $null = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle
            $createdTables = @((Invoke-DbaQuery @splatTableLookup).name)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Whatever name the replay gave the table, it starts with the prefix.
            foreach ($createdTable in (Invoke-DbaQuery @splatTableLookup).name) {
                $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "DROP TABLE dbo.[$createdTable];"
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates the table with the name it was given" {
            $createdTables | Should -BeExactly $tableName
        }
    }

    Context "Removing the replay file" {
        BeforeAll {
            # The replay file holds the captured statements, so it is removed also when the replay fails, here because the
            # instance does not exist and -EnableException turns the failure into an exception.
            $tempPath = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
            $replayFilesBefore = @((Get-ChildItem -Path $tempPath -Filter "dbatools-replay-*.sql").FullName)
            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "SELECT 1 AS dbatoolsci_replay_cleanup"
            }
            $replayError = $null
            try {
                $null = $batch | Invoke-DbaXEReplay -SqlInstance "dbatoolsci-nohost-$(Get-Random)" -EnableException
            } catch {
                $replayError = $PSItem
            }
            $replayFilesLeft = @(Get-ChildItem -Path $tempPath -Filter "dbatools-replay-*.sql" | Where-Object FullName -notin $replayFilesBefore)
        }

        AfterAll {
            if ($replayFilesLeft) {
                Remove-Item -Path $replayFilesLeft.FullName -ErrorAction SilentlyContinue
            }
        }

        It "fails for an instance that does not exist" {
            $replayError | Should -Not -BeNullOrEmpty
        }

        It "removes the replay file after the failure" {
            $replayFilesLeft | Should -BeNullOrEmpty
        }
    }

    Context "Reporting a replay that sqlcmd cannot run" {
        BeforeAll {
            # Connect-DbaInstance does not open the database, sqlcmd does, so a database that does not exist lets the
            # connection of dbatools succeed and sqlcmd exit with a code other than 0 without replaying anything.
            $missingDatabase = "dbatoolsci_nodb_$(Get-Random)"
            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "SELECT 1 AS dbatoolsci_replay_nodb"
            }
            $null = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -Database $missingDatabase -WarningAction SilentlyContinue
            $replayWarning = $WarnVar
            $replayException = $null
            try {
                $null = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -Database $missingDatabase -EnableException
            } catch {
                $replayException = $PSItem
            }
        }

        It "warns that sqlcmd could not replay the file" {
            ($replayWarning -join " ") | Should -BeLike "*sqlcmd could not replay the file*$missingDatabase*exit code*"
        }

        It "throws the same with -EnableException" {
            $replayException.Exception.Message | Should -BeLike "*sqlcmd could not replay the file*$missingDatabase*exit code*"
        }
    }

    Context "Replaying as a SQL login" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # sqlcmd gets the password through the environment variable SQLCMDPASSWORD, so it never shows on the command
            # line of sqlcmd, where every user of the computer can read it. A second runspace collects the command lines of
            # the sqlcmd processes that this process starts, while the replayed batch waits for three seconds.
            $replayLogin = "dbatoolsci_replay_$(Get-Random)"
            $replayPassword = "P@ssw0rd$(Get-Random)!"
            $securePassword = ConvertTo-SecureString -String $replayPassword -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $replayLogin -SecurePassword $securePassword
            $replayCredential = New-Object System.Management.Automation.PSCredential($replayLogin, $securePassword)
            $trustsCertificate = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).ConnectionContext.TrustServerCertificate

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # A value of the caller, which the command has to put back.
            $callerPassword = "dbatoolsci_caller_value"
            [Environment]::SetEnvironmentVariable("SQLCMDPASSWORD", $callerPassword)

            $watcher = [powershell]::Create()
            $null = $watcher.AddScript( {
                    param($ParentId)
                    $commandLines = @()
                    $waitUntil = (Get-Date).AddSeconds(30)
                    while ((Get-Date) -lt $waitUntil) {
                        $running = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $ParentId" | Where-Object Name -eq "sqlcmd.exe")
                        foreach ($process in $running) {
                            $commandLines += $process.CommandLine
                        }
                        if ($commandLines.Count -gt 0 -and $running.Count -eq 0) {
                            break
                        }
                        Start-Sleep -Milliseconds 100
                    }
                    $commandLines | Select-Object -Unique
                }).AddArgument($PID)
            $watcherHandle = $watcher.BeginInvoke()

            $batch = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                batch_text = "DECLARE @delay datetime = DATEADD(SECOND, 3, 0); WAITFOR DELAY @delay; SELECT SUSER_SNAME() AS dbatoolsci_login;"
            }
            $results = $batch | Invoke-DbaXEReplay -SqlInstance $TestConfig.InstanceSingle -SqlCredential $replayCredential
            $passwordAfter = [Environment]::GetEnvironmentVariable("SQLCMDPASSWORD")
            $sqlcmdCommandLines = @($watcher.EndInvoke($watcherHandle))
            $watcher.Dispose()
        }

        AfterAll {
            [Environment]::SetEnvironmentVariable("SQLCMDPASSWORD", $null)

            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command connected as the login through the connection pool, so -Force ends that session first.
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $replayLogin -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "replays as the login" {
            ($results -join " ") | Should -BeLike "*$replayLogin*"
        }

        It "does not put the password on the command line of sqlcmd" {
            $sqlcmdCommandLines | Should -Not -BeNullOrEmpty
            ($sqlcmdCommandLines -join " ") | Should -Not -Match ([regex]::Escape($replayPassword))
        }

        It "lets sqlcmd trust the server certificate exactly when the connection of dbatools does" {
            ($sqlcmdCommandLines -join " ") -match "\s-C(\s|$)" | Should -Be $trustsCertificate
        }

        It "puts back the value of SQLCMDPASSWORD that the caller had" {
            $passwordAfter | Should -BeExactly $callerPassword
        }
    }
}
