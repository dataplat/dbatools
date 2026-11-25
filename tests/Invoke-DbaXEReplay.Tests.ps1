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
}
