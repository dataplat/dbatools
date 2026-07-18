#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaAgFailover",
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
                "AvailabilityGroup",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: an actual failover requires a live multi-replica Availability Group, which
    # the standalone InstanceSingle does not provide - that leg is DEFERRED-TO-AG01 per the
    # coordinator AG policy (the AG01 smoke supplies the live failover evidence). What IS
    # characterizable on a standalone instance is the guard chain that runs BEFORE any failover:
    # two parameter guards that fire before any connection is made, and the resolution path through
    # Get-DbaAvailabilityGroup, which on a non-HADR instance warns once and yields nothing, so the
    # failover loop never runs. Every call below also passes WhatIf: the guards fire either way
    # (they are plain warnings, not gated actions), and a surprise environment with a live matching
    # Availability Group still could not be failed over by a characterization test.
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $isHadrEnabled = $server.IsHadrEnabled
        $random = Get-Random
        $instanceToken = "$([DbaInstanceParameter]$TestConfig.InstanceSingle)"
    }

    Context "Guarding before the failover" {
        It "Warns once and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaAgFailover @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -SqlInstance or an Input Object"
        }

        It "Warns once and returns nothing when SqlInstance is supplied without AvailabilityGroup" {
            $splatNoAgName = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaAgFailover @splatNoAgName)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify at least one availability group when using SqlInstance."
        }

        It "Fails over nothing when the requested Availability Group does not exist" {
            $splatAbsentAg = @{
                SqlInstance       = $TestConfig.InstanceSingle
                AvailabilityGroup = "dbatoolsci_noag_$random"
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
                WhatIf            = $true
            }
            $result = @(Invoke-DbaAgFailover @splatAbsentAg)
            $result.Count | Should -Be 0

            if ($isHadrEnabled) {
                # An HADR-enabled instance filters the absent name silently: the nested
                # Get-DbaAvailabilityGroup emits no warning for a non-matching name, nothing
                # resolves, and the failover loop never runs.
                $warn.Count | Should -Be 0
            } else {
                # A non-HADR instance warns exactly once, from the nested Get-DbaAvailabilityGroup
                # resolution; Invoke-DbaAgFailover adds no warning of its own and the failover loop
                # never runs.
                $warn.Count | Should -Be 1
                $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                $payload | Should -Be "Availability Group (HADR) is not configured for the instance: $instanceToken."
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # DISPOSABLE-AG LEG: the guard-chain block above characterizes the paths that run before the
    # failover loop; this block adds the coverage those paths cannot - a REAL AvailabilityGroup
    # object resolving all the way into the failover loop and the inner ShouldProcess gate of the port.
    # It builds a disposable clusterless (ClusterType None) availability group on InstanceHadr using
    # the same fixture pattern as the New-DbaAvailabilityGroup suite, and never touches the read-only
    # lab AG01. A single-replica clusterless AG has no synchronized secondary to receive a failover,
    # so a SUCCESSFUL failover cannot be demonstrated here (that mutation remains DEFERRED - it needs
    # a multi-replica topology the disposable AG cannot provide, and AG01 must never be failed over).
    # What a real resolved AG DOES prove: the -WhatIf gate suppresses the failover with no output, and
    # a forced attempt enters the per-AG loop and is contained as a non-terminating result. Two
    # preconditions legitimately vary by environment and skip rather than fail - the instance being
    # HADR-enabled and the shared AG certificate being present; any failure past those preconditions
    # is a real fixture regression and is allowed to throw. Teardown touches only what this fixture
    # created and cleans each resource independently.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException so a genuine setup
        # failure surfaces rather than silently skipping the tests.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $agName = "dbatoolsci_agfailover_$(Get-Random)"
        $agDbName = "dbatoolsci_agfailoverdb_$(Get-Random)"
        $agBackupPath = "$($TestConfig.Temp)\Invoke-DbaAgFailover-$(Get-Random)"

        # Teardown runs on creation ATTEMPT, not on post-hoc discovery: each flag is set immediately
        # BEFORE its create call, so a resource that was created just before a mid-setup throw (or
        # created but momentarily unresolvable) is still reclaimed by its exact randomized name, and a
        # removal of something that never got created is a harmless no-op.
        $agReady = $false
        $agSkipReason = $null
        $resolvedAg = $null
        $baselineCaptured = $false
        $preExistingEndpoints = @()
        $agCreated = $false
        $dbCreated = $false
        $backupDirCreated = $false
        $createdEndpointNames = @()

        try {
            $hadrServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr
            if (-not $hadrServer.IsHadrEnabled) {
                $agSkipReason = "InstanceHadr is not HADR-enabled"
            } elseif (-not $hadrServer.Databases["master"].Certificates["dbatoolsci_AGCert"]) {
                $agSkipReason = "the dbatoolsci_AGCert certificate is not present in master on InstanceHadr"
            } else {
                # Baseline the mirroring endpoints BEFORE any creation; only once this succeeds is the
                # created-endpoint delta meaningful, so it can never classify a pre-existing endpoint
                # as fixture-created.
                $splatBaselineEndpoint = @{
                    SqlInstance = $TestConfig.InstanceHadr
                    Type        = "DatabaseMirroring"
                }
                $preExistingEndpoints = @(Get-DbaEndpoint @splatBaselineEndpoint).Name
                $baselineCaptured = $true

                $backupDirCreated = $true
                $splatBackupDir = @{
                    Path        = $agBackupPath
                    ItemType    = "Directory"
                    ErrorAction = "Stop"
                }
                $null = New-Item @splatBackupDir

                $dbCreated = $true
                $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $agDbName

                $splatBackup = @{
                    SqlInstance = $TestConfig.InstanceHadr
                    Database    = $agDbName
                    FilePath    = "$agBackupPath\$agDbName.bak"
                }
                $null = Backup-DbaDatabase @splatBackup

                $agCreated = $true
                $splatNewAg = @{
                    Primary      = $TestConfig.InstanceHadr
                    Name         = $agName
                    ClusterType  = "None"
                    FailoverMode = "Manual"
                    Database     = $agDbName
                    Certificate  = "dbatoolsci_AGCert"
                }
                $null = New-DbaAvailabilityGroup @splatNewAg

                # Keep the resolved group for the It blocks so they exercise the failover loop through
                # -InputObject rather than re-resolving; a created-but-unresolvable group is a
                # regression, not an environmental precondition, so throw rather than skip.
                $resolvedAg = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
                if (-not $resolvedAg) {
                    throw "created availability group $agName but Get-DbaAvailabilityGroup could not resolve it"
                }
                $agReady = $true
            }
        } finally {
            # Restore the EnableException default FIRST, before the fallible endpoint delta below, so a
            # delta error can neither mask the setup outcome nor leave the default enabled.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The created-endpoint delta needs the actual names; isolate it so it cannot throw out of
            # the finally, and only compute it when the pre-creation baseline succeeded.
            if ($baselineCaptured) {
                try {
                    $splatDeltaEndpoint = @{
                        SqlInstance = $TestConfig.InstanceHadr
                        Type        = "DatabaseMirroring"
                        ErrorAction = "SilentlyContinue"
                    }
                    $postEndpoints = @(Get-DbaEndpoint @splatDeltaEndpoint).Name
                    $createdEndpointNames = @($postEndpoints | Where-Object { $PSItem -notin $preExistingEndpoints })
                } catch {
                    $createdEndpointNames = @()
                }
            }
        }
    }

    AfterAll {
        # We want to run cleanup with EnableException so a failure to remove a created object surfaces
        # loudly rather than silently leaking lab state - but each removal is isolated so one failure
        # cannot strand the rest; the collected failures are reported after every attempt.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $cleanupErrors = New-Object System.Collections.Generic.List[string]

        if ($agCreated) {
            try {
                $splatRemoveAg = @{
                    SqlInstance       = $TestConfig.InstanceHadr
                    AvailabilityGroup = $agName
                }
                $null = Remove-DbaAvailabilityGroup @splatRemoveAg
            } catch {
                $cleanupErrors.Add("availability group ${agName}: $($_.Exception.Message)")
            }
        }
        if ($createdEndpointNames.Count -gt 0) {
            try {
                $splatRemoveEndpoint = @{
                    SqlInstance = $TestConfig.InstanceHadr
                    Type        = "DatabaseMirroring"
                    Endpoint    = $createdEndpointNames
                }
                $null = Get-DbaEndpoint @splatRemoveEndpoint | Remove-DbaEndpoint
            } catch {
                $cleanupErrors.Add("endpoints $($createdEndpointNames -join ", "): $($_.Exception.Message)")
            }
        }
        if ($dbCreated) {
            try {
                $splatRemoveDb = @{
                    SqlInstance = $TestConfig.InstanceHadr
                    Database    = $agDbName
                }
                $null = Remove-DbaDatabase @splatRemoveDb
            } catch {
                $cleanupErrors.Add("database ${agDbName}: $($_.Exception.Message)")
            }
        }
        if ($backupDirCreated -and (Test-Path -Path $agBackupPath)) {
            try {
                $splatRemoveBackup = @{
                    Path        = $agBackupPath
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = "Stop"
                }
                Remove-Item @splatRemoveBackup
            } catch {
                $cleanupErrors.Add("backup directory ${agBackupPath}: $($_.Exception.Message)")
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        if ($cleanupErrors.Count -gt 0) {
            throw "disposable availability group teardown left state behind: $($cleanupErrors -join "; ")"
        }
    }

    Context "Against a disposable availability group" {
        It "Honors -WhatIf and does not fail over the resolved availability group" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because "no resolvable disposable availability group on InstanceHadr: $agSkipReason"
                return
            }
            # Pass the resolved group directly through -InputObject so the loop runs on a known-present
            # object and the assertion can never pass on an empty re-resolution.
            $splatWhatIf = @{
                InputObject     = $resolvedAg
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Invoke-DbaAgFailover @splatWhatIf)
            # Under -WhatIf ShouldProcess returns false, so neither Failover nor
            # FailoverWithPotentialDataLoss is called: no output and no Failure warning. A broken gate
            # would instead attempt the failover on this present group and surface a Failure warning.
            $result.Count | Should -Be 0
            $warn -join "" | Should -Not -Match "Failure"
        }

        It "Enters the failover loop for the resolved group and contains the outcome" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because "no resolvable disposable availability group on InstanceHadr: $agSkipReason"
                return
            }
            $splatForce = @{
                InputObject     = $resolvedAg
                Force           = $true
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $result = @(Invoke-DbaAgFailover @splatForce)
            # A forced failover of the present group enters the per-AG loop and produces a specific
            # observable: the availability group object emitted for $agName on success, or a contained
            # Failure warning when a single-replica clusterless group has no secondary to receive the
            # failover. Either is non-terminating (EnableException is off); direct invocation already
            # enforces the no-throw invariant. The specific branch depends on the replica topology.
            $emittedGroup = @($result | Where-Object { $PSItem.Name -eq $agName })
            $failureWarned = @($warn) -join "" -match "Failure"
            ($emittedGroup.Count -gt 0 -or $failureWarned) | Should -BeTrue
        }
    }
}
