#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbLogShipping",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "PrimarySqlInstance",
                "SecondarySqlInstance",
                "PrimarySqlCredential",
                "SecondarySqlCredential",
                "Database",
                "RemoveSecondaryDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Zero-test remediation (W4-049): the old placeholder Describe was commented out whole, so
    # gate runs executed nothing. This suite reuses the PROBED-precondition pattern proven by
    # Invoke-DbaDbLogShipping.Tests.ps1 on the same instance pair: preconditions (running SQL
    # Agent on both instances, UNC shared path) are probed and unmet ones produce an explicit
    # per-It skip reason - never an empty run.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $primaryDb = "dbatoolsci_removels"
        $secondaryDb = "dbatoolsci_removels_LS"

        $logShippingReady = $false
        # Distinct outcomes (codex r4): unmet ENVIRONMENT preconditions (Agent/UNC) SKIP with a
        # reason; setup ERRORS or a non-materialized configuration FAIL the tests - a green
        # gate must mean the removal was actually exercised, never that setup quietly broke.
        $preconditionSkipReason = $null
        $setupFailure = $null
        try {
            $agentQuery = "SELECT status_desc FROM sys.dm_server_services WHERE servicename LIKE 'SQL Server Agent%'"
            $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $secondaryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            if (@($primaryServer.Query($agentQuery)).status_desc -notcontains "Running") {
                $preconditionSkipReason = "SQL Agent is not running on the primary instance"
            } elseif (@($secondaryServer.Query($agentQuery)).status_desc -notcontains "Running") {
                $preconditionSkipReason = "SQL Agent is not running on the secondary instance"
            } elseif ($TestConfig.Temp -notmatch "^\\\\") {
                $preconditionSkipReason = "TestConfig.Temp is not a UNC path and log shipping setup requires the shared path in UNC form"
            } else {
                $null = $primaryServer.Query("CREATE DATABASE $primaryDb")
                $null = $primaryServer.Query("ALTER DATABASE $primaryDb SET RECOVERY FULL")
                $splatLogShipping = @{
                    SourceSqlInstance       = $TestConfig.InstanceMulti1
                    DestinationSqlInstance  = $TestConfig.InstanceMulti2
                    Database                = $primaryDb
                    SharedPath              = $TestConfig.Temp
                    GenerateFullBackup      = $true
                    SecondaryDatabaseSuffix = "_LS"
                    Force                   = $true
                }
                $setupResult = Invoke-DbaDbLogShipping @splatLogShipping
                if ($setupResult.Result -ne "Success") {
                    $setupFailure = "log shipping setup returned $($setupResult.Result)"
                } else {
                    # Readiness requires the CONFIGURATION to verifiably exist, not just a
                    # Success result - otherwise the removal tests' absence assertions could
                    # pass vacuously against a setup that never materialized (codex r1).
                    $primaryRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database msdb -Query "SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$primaryDb'"
                    $secondaryRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Database msdb -Query "SELECT secondary_database FROM msdb.dbo.log_shipping_secondary_databases WHERE secondary_database = '$secondaryDb'"
                    $secondaryDbObject = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $secondaryDb
                    if (-not $primaryRow -or -not $secondaryRow -or -not $secondaryDbObject) {
                        $setupFailure = "setup reported Success but the log shipping configuration did not fully materialize (primary row: $([bool]$primaryRow), secondary row: $([bool]$secondaryRow), secondary db: $([bool]$secondaryDbObject))"
                    } else {
                        $logShippingReady = $true
                    }
                }
            }
        } catch {
            $setupFailure = $_.Exception.Message
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the cleanup fails loudly.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clear any residual log shipping configuration FIRST: dropping the databases while
        # msdb still holds primary/secondary rows leaves orphaned agent jobs behind on the
        # shared pair when the removal under test failed or was partial (codex r1).
        # EnableException must be explicitly OFF here: the Before/AfterAll default would make
        # this replay THROW on the already-clean green path (config absent after successful
        # tests) and abort the remaining cleanup (codex r5). The idempotent procedure cleanup
        # below covers every partial state; this replay is only the best-effort first pass.
        $splatResidual = @{
            PrimarySqlInstance      = $TestConfig.InstanceMulti1
            SecondarySqlInstance    = $TestConfig.InstanceMulti2
            Database                = $primaryDb
            RemoveSecondaryDatabase = $true
            Confirm                 = $false
            EnableException         = $false
            ErrorAction             = "SilentlyContinue"
        }
        $null = Remove-DbaDbLogShipping @splatResidual

        # The replay cannot clear SECONDARY-ONLY residue once the primary row is gone (the
        # command works from the primary side), so each side's msdb configuration is removed
        # directly through the system procedures as well - both tolerate absent state under
        # SilentlyContinue, so full, partial and clean outcomes all converge (codex r2).
        $splatPrimaryResidual = @{
            SqlInstance = $TestConfig.InstanceMulti1
            Database    = "msdb"
            Query       = "IF EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$primaryDb') BEGIN EXEC master.dbo.sp_delete_log_shipping_primary_secondary @primary_database = '$primaryDb', @secondary_server = '$($TestConfig.InstanceMulti2)', @secondary_database = '$secondaryDb'; EXEC master.dbo.sp_delete_log_shipping_primary_database @database = '$primaryDb' END"
            ErrorAction = "SilentlyContinue"
        }
        $null = Invoke-DbaQuery @splatPrimaryResidual
        $splatSecondaryResidual = @{
            SqlInstance = $TestConfig.InstanceMulti2
            Database    = "msdb"
            Query       = "IF EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_secondary_databases WHERE secondary_database = '$secondaryDb') EXEC master.dbo.sp_delete_log_shipping_secondary_database @secondary_database = '$secondaryDb'"
            ErrorAction = "SilentlyContinue"
        }
        $null = Invoke-DbaQuery @splatSecondaryResidual

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $primaryDb -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $secondaryDb -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $TestConfig.Temp $primaryDb) -Recurse -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Removing log shipping" {
        It "Removes the log shipping configuration from the primary" {
            if ($preconditionSkipReason) {
                Set-ItResult -Skipped -Because "log shipping preconditions not met on this pair: $preconditionSkipReason"
                return
            }
            if (-not $logShippingReady) {
                throw "log shipping setup FAILED (not a skippable precondition): $setupFailure"
            }
            $splatRemove = @{
                PrimarySqlInstance      = $TestConfig.InstanceMulti1
                SecondarySqlInstance    = $TestConfig.InstanceMulti2
                Database                = $primaryDb
                RemoveSecondaryDatabase = $true
                Confirm                 = $false
            }
            Remove-DbaDbLogShipping @splatRemove

            $primaryConfig = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database msdb -Query "SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$primaryDb'"
            $primaryConfig | Should -BeNullOrEmpty
        }

        It "Removes the secondary configuration and database when requested" {
            if ($preconditionSkipReason) {
                Set-ItResult -Skipped -Because "log shipping preconditions not met on this pair: $preconditionSkipReason"
                return
            }
            if (-not $logShippingReady) {
                throw "log shipping setup FAILED (not a skippable precondition): $setupFailure"
            }
            $secondaryConfig = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Database msdb -Query "SELECT secondary_database FROM msdb.dbo.log_shipping_secondary_databases WHERE secondary_database = '$secondaryDb'"
            $secondaryConfig | Should -BeNullOrEmpty
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $secondaryDb) | Should -BeNullOrEmpty
        }
    }
}
