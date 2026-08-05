#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaStartupProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Procedure",
                "ExcludeProcedure",
                "Force",
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

        # Set variables. They are available in all the It blocks.
        $procAlpha = "dbatoolsci_startup_alpha"
        $procBeta  = "dbatoolsci_startup_beta"
        $procGamma = "dbatoolsci_startup_gamma"
        $procPlain = "dbatoolsci_plain_delta"
        $allProcs  = @($procAlpha, $procBeta, $procGamma, $procPlain)

        # Each body carries its own marker so a definition read off the destination identifies
        # which source procedure it actually came from.
        function Get-DestinationProcedureState {
            param($ProcedureName)

            $splatState = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$ProcedureName')) AS Definition, (SELECT is_auto_executed FROM sys.procedures WHERE name = '$ProcedureName' AND schema_id = SCHEMA_ID('dbo')) AS IsAutoExecuted"
            }
            Invoke-DbaQuery @splatState
        }

        # Clean both ends first - a leftover startup procedure from an interrupted run would make
        # the -WhatIf absence assertion pass for the wrong reason.
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($proc in $allProcs) {
                Invoke-DbaQuery -SqlInstance $instance -Database "master" -Query "IF OBJECT_ID('dbo.$proc') IS NOT NULL DROP PROCEDURE dbo.$proc"
            }
        }

        # Create the objects.
        foreach ($proc in $procAlpha, $procBeta, $procGamma, $procPlain) {
            $marker = "$proc-v1"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database "master" -Query "CREATE PROCEDURE dbo.$proc AS SELECT '$marker' AS Marker"
        }

        # Only the first three are flagged for startup - the fourth proves the ExecIsStartup filter.
        foreach ($proc in $procAlpha, $procBeta, $procGamma) {
            $splatStartup = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "EXEC sp_procoption @ProcName = N'$proc', @OptionName = 'startup', @OptionValue = 'on'"
            }
            Invoke-DbaQuery @splatStartup
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects. A startup procedure left behind would execute on every
        # instance restart, so this drops from both ends whether or not the copy legs ran.
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($proc in $allProcs) {
                Invoke-DbaQuery -SqlInstance $instance -Database "master" -Query "IF OBJECT_ID('dbo.$proc') IS NOT NULL DROP PROCEDURE dbo.$proc"
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When previewing with -WhatIf" {
        BeforeAll {
            $splatWhatIf = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = $procAlpha
                WhatIf      = $true
            }
            $whatIfResults = Copy-DbaStartupProcedure @splatWhatIf

            $whatIfState = Get-DestinationProcedureState -ProcedureName $procAlpha
        }

        It "Should return no result objects" {
            $whatIfResults | Should -BeNullOrEmpty
        }

        It "Should not create the procedure on the destination" {
            $whatIfState.Definition | Should -BeNullOrEmpty
        }
    }

    Context "When copying multiple startup procedures in one call" {
        BeforeAll {
            $splatMulti = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = @($procAlpha, $procBeta)
            }
            $multiResults = Copy-DbaStartupProcedure @splatMulti

            $alphaState = Get-DestinationProcedureState -ProcedureName $procAlpha
            $betaState  = Get-DestinationProcedureState -ProcedureName $procBeta
        }

        It "Should report both procedures as Successful" {
            $statuses = $multiResults | Where-Object Name -in $procAlpha, $procBeta | Select-Object -ExpandProperty Status
            $statuses.Count | Should -Be 2
            $statuses | Should -Not -Contain "Failed"
            ($statuses | Sort-Object -Unique) | Should -Be "Successful"
        }

        It "Should land each procedure with its own body, not the first record's" {
            $alphaState.Definition | Should -BeLike "*$procAlpha-v1*"
            $betaState.Definition | Should -BeLike "*$procBeta-v1*"
        }

        It "Should flag both procedures for startup on the destination" {
            $alphaState.IsAutoExecuted | Should -Be 1
            $betaState.IsAutoExecuted | Should -Be 1
        }
    }

    Context "When the procedure already exists on the destination" {
        BeforeAll {
            $splatSkip = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = $procAlpha
            }
            $skipResults = Copy-DbaStartupProcedure @splatSkip

            $skipState = Get-DestinationProcedureState -ProcedureName $procAlpha
        }

        It "Should report the procedure as Skipped" {
            $skipped = $skipResults | Where-Object Name -eq $procAlpha
            $skipped.Status | Should -Be "Skipped"
            $skipped.Notes | Should -Be "Already exists on destination"
        }

        It "Should leave the destination body untouched" {
            $skipState.Definition | Should -BeLike "*$procAlpha-v1*"
        }
    }

    Context "When -Force overwrites an existing startup procedure" {
        BeforeAll {
            $splatAlter = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = "master"
                Query           = "ALTER PROCEDURE dbo.$procAlpha AS SELECT '$procAlpha-v2' AS Marker"
                EnableException = $true
            }
            Invoke-DbaQuery @splatAlter

            $splatForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = $procAlpha
                Force       = $true
            }
            $forceResults = Copy-DbaStartupProcedure @splatForce

            $forceState = Get-DestinationProcedureState -ProcedureName $procAlpha
        }

        It "Should report the procedure as Successful" {
            $forced = $forceResults | Where-Object Name -eq $procAlpha
            $forced.Status | Should -Be "Successful"
        }

        It "Should replace the destination body with the newer source body" {
            $forceState.Definition | Should -BeLike "*$procAlpha-v2*"
        }

        It "Should still flag the recreated procedure for startup" {
            $forceState.IsAutoExecuted | Should -Be 1
        }
    }

    Context "When -WhatIf reports the operations it would perform" {
        BeforeAll {
            # ShouldProcess writes its WhatIf line straight to the host and is not reachable by
            # stream redirection on either edition, so a transcript is the only in-process capture.
            $transcriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatoolsci_startupproc_whatif_$([guid]::NewGuid().ToString("N")).log"

            Start-Transcript -Path $transcriptPath | Out-Null
            try {
                # Gamma is not on the destination yet, so this reaches the create action; alpha is,
                # so it reaches the already-exists action and, with -Force, the drop-and-recreate one.
                $splatCreateAction = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Procedure   = $procGamma
                    WhatIf      = $true
                }
                $null = Copy-DbaStartupProcedure @splatCreateAction

                $splatExistsAction = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Procedure   = $procAlpha
                    WhatIf      = $true
                }
                $null = Copy-DbaStartupProcedure @splatExistsAction

                $splatForceAction = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Procedure   = $procAlpha
                    Force       = $true
                    WhatIf      = $true
                }
                $null = Copy-DbaStartupProcedure @splatForceAction
            } finally {
                Stop-Transcript | Out-Null
            }

            $whatIfTranscript = Get-Content -Path $transcriptPath -Raw
            Remove-Item -Path $transcriptPath -Force -ErrorAction SilentlyContinue
        }

        It "Should report the create action verbatim" {
            $whatIfTranscript | Should -BeLike "*Creating startup procedure dbo.$procGamma*"
        }

        It "Should report the already-exists action verbatim" {
            $whatIfTranscript | Should -BeLike "*Startup procedure dbo.$procAlpha exists at destination. Use -Force to drop and migrate.*"
        }

        It "Should report the force drop-and-recreate action verbatim" {
            $whatIfTranscript | Should -BeLike "*Dropping startup procedure dbo.$procAlpha and recreating*"
        }
    }

    # This Context doubles as the absence control for the one above: it copies gamma for real and
    # expects Successful, which only holds if the -WhatIf create above did not actually create it.
    Context "When -ExcludeProcedure is used without -Procedure" {
        BeforeAll {
            $splatExclude = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                ExcludeProcedure = @($procAlpha, $procBeta)
            }
            $excludeResults = Copy-DbaStartupProcedure @splatExclude

            $gammaState = Get-DestinationProcedureState -ProcedureName $procGamma
            $plainState = Get-DestinationProcedureState -ProcedureName $procPlain
        }

        It "Should copy the procedure that was not excluded" {
            ($excludeResults | Where-Object Name -eq $procGamma).Status | Should -Be "Successful"
            $gammaState.Definition | Should -BeLike "*$procGamma-v1*"
            $gammaState.IsAutoExecuted | Should -Be 1
        }

        It "Should report nothing at all for the excluded procedures" {
            $excludeResults | Where-Object Name -in $procAlpha, $procBeta | Should -BeNullOrEmpty
        }

        It "Should not copy a procedure that is not flagged for startup" {
            $excludeResults | Where-Object Name -eq $procPlain | Should -BeNullOrEmpty
            $plainState.Definition | Should -BeNullOrEmpty
        }
    }
}
