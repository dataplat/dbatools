#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaXESession.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "InputObject",
                "AddEvent",
                "RemoveEvent",
                "AutoStart",
                "MaxMemory",
                "MaxDispatchLatency",
                "MaxEventSize",
                "EventRetentionMode",
                "MemoryPartitionMode",
                "TrackCausality",
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

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Each behavioral leg gets its OWN session so the tests do not couple through shared state. A session
        # is only persisted (and therefore listable by Get-DbaXESession) once it carries at least one event, so
        # the fixtures are created directly with an event via T-SQL rather than New-DbaXESession (empty).
        $sessionMaxMem = "dbatoolsci_xe_maxmem_$random"
        $sessionEvent = "dbatoolsci_xe_event_$random"
        $sessionWhatIf = "dbatoolsci_xe_whatif_$random"
        $sessionPipe1 = "dbatoolsci_xe_pipe1_$random"
        $sessionPipe2 = "dbatoolsci_xe_pipe2_$random"
        $allSessions = @($sessionMaxMem, $sessionEvent, $sessionWhatIf, $sessionPipe1, $sessionPipe2)

        foreach ($sessionName in $allSessions) {
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Query "CREATE EVENT SESSION [$sessionName] ON SERVER ADD EVENT sqlserver.sql_statement_completed;"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaXESession -SqlInstance $InstanceSingle -Session $allSessions -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the alter and changes nothing" {
            # Alter validation can create a transient server-side session (a "dummy_session"), so WhatIf must
            # gate the Alter and leave the session untouched. The ShouldProcess text is emitted from the
            # module-scoped hop body and is host-direct (it does not reliably reach an in-process transcript),
            # so the distinguishing assertion is that the side effect did NOT happen.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Session     = $sessionWhatIf
                MaxMemory   = 8192
                WhatIf      = $true
            }
            Set-DbaXESession @splatWhatIf

            # The side effect did NOT happen: the memory is still the default.
            $unchanged = Get-DbaXESession -SqlInstance $InstanceSingle -Session $sessionWhatIf
            $unchanged.MaxMemory | Should -Not -Be 8192
        }
    }

    Context "Command behavior" {
        It "Alters a session option via -SqlInstance and re-emits the decorated object" {
            $splatMaxMem = @{
                SqlInstance     = $InstanceSingle
                Session         = $sessionMaxMem
                MaxMemory       = 8192
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaXESession @splatMaxMem
            $result.MaxMemory | Should -Be 8192
            # Decoration parity with Get-DbaXESession so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            # Read back independently.
            (Get-DbaXESession -SqlInstance $InstanceSingle -Session $sessionMaxMem).MaxMemory | Should -Be 8192
        }

        It "Adds and then removes an event" {
            # The fixture already carries sqlserver.sql_statement_completed; add/remove a DIFFERENT event.
            $added = Set-DbaXESession -SqlInstance $InstanceSingle -Session $sessionEvent -AddEvent "sqlserver.sql_batch_completed" -Confirm:$false -EnableException
            $added.Events.Name | Should -Contain "sqlserver.sql_batch_completed"

            $removed = Set-DbaXESession -SqlInstance $InstanceSingle -Session $sessionEvent -RemoveEvent "sqlserver.sql_batch_completed" -Confirm:$false -EnableException
            $removed.Events.Name | Should -Not -Contain "sqlserver.sql_batch_completed"
        }

        It "Processes multiple piped sessions (N in, N out)" {
            # Multi-record piped leg. Two distinct sessions piped in from Get-DbaXESession must both come back
            # altered, each resolving its own parent server.
            $results = Get-DbaXESession -SqlInstance $InstanceSingle -Session $sessionPipe1, $sessionPipe2 |
                Set-DbaXESession -TrackCausality -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.TrackCausality | Sort-Object -Unique | Should -Be $true
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Session         = $sessionMaxMem
                MaxMemory       = 4096
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaXESession @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues on an unknown session without -EnableException" {
            $splatWarn = @{
                SqlInstance        = $InstanceSingle
                Session            = "dbatoolsci_does_not_exist_$random", $sessionMaxMem
                MaxDispatchLatency = 45
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warn"
            }
            $results = Set-DbaXESession @splatWarn
            $warn | Should -Not -BeNullOrEmpty
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Session         = "dbatoolsci_does_not_exist_$random"
                MaxMemory       = 4096
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaXESession @splatThrow } | Should -Throw
        }
    }
}
