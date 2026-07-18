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

        # Track exactly what this fixture creates so teardown removes only its own objects.
        $agReady = $false
        $agCreated = $false
        $dbCreated = $false
        $backupDirCreated = $false
        $enteredCreation = $false
        $createdEndpointNames = @()
        $preExistingEndpoints = @()
        $agSkipReason = $null

        try {
            $hadrServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr
            if (-not $hadrServer.IsHadrEnabled) {
                $agSkipReason = "InstanceHadr is not HADR-enabled"
            } elseif (-not $hadrServer.Databases["master"].Certificates["dbatoolsci_AGCert"]) {
                $agSkipReason = "the dbatoolsci_AGCert certificate is not present in master on InstanceHadr"
            } else {
                $enteredCreation = $true
                # Record the mirroring endpoints that already exist so the delta below identifies only
                # what this fixture creates; New-DbaAvailabilityGroup creates the hadr_endpoint it owns.
                $preExistingEndpoints = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring).Name

                $splatBackupDir = @{
                    Path        = $agBackupPath
                    ItemType    = "Directory"
                    ErrorAction = "Stop"
                }
                $null = New-Item @splatBackupDir
                $backupDirCreated = $true

                $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $agDbName
                $dbCreated = $true

                $splatBackup = @{
                    SqlInstance = $TestConfig.InstanceHadr
                    Database    = $agDbName
                    FilePath    = "$agBackupPath\$agDbName.bak"
                }
                $null = Backup-DbaDatabase @splatBackup

                $splatNewAg = @{
                    Primary      = $TestConfig.InstanceHadr
                    Name         = $agName
                    ClusterType  = "None"
                    FailoverMode = "Manual"
                    Database     = $agDbName
                    Certificate  = "dbatoolsci_AGCert"
                }
                $null = New-DbaAvailabilityGroup @splatNewAg
                $agCreated = $true

                # The resolution path of the command must positively find the group, else the It
                # assertions would pass vacuously against an empty loop. A created-but-unresolvable
                # group is a regression, not an environmental precondition, so throw rather than skip.
                $resolvedAg = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
                if (-not $resolvedAg) {
                    throw "created availability group $agName but Get-DbaAvailabilityGroup could not resolve it"
                }
                $agReady = $true
            }
        } finally {
            # Even when setup throws mid-way, capture any endpoint this fixture created (the AG create
            # can make the hadr_endpoint before a later step fails) so teardown can reclaim it, and
            # always restore the EnableException default so AfterAll cleanup runs without it.
            if ($enteredCreation) {
                $postEndpoints = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring -ErrorAction SilentlyContinue).Name
                $createdEndpointNames = @($postEndpoints | Where-Object { $PSItem -notin $preExistingEndpoints })
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    AfterAll {
        # Clean each created resource INDEPENDENTLY so one failure cannot strand the rest, and touch
        # only what this fixture created. EnableException stays off here: a cleanup failure surfaces
        # as a warning rather than masking a genuine test result.
        if ($agCreated) {
            $splatRemoveAg = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                ErrorAction       = "SilentlyContinue"
            }
            $null = Remove-DbaAvailabilityGroup @splatRemoveAg
        }
        if ($createdEndpointNames.Count -gt 0) {
            $splatRemoveEndpoint = @{
                SqlInstance = $TestConfig.InstanceHadr
                Type        = "DatabaseMirroring"
                Endpoint    = $createdEndpointNames
                ErrorAction = "SilentlyContinue"
            }
            $null = Get-DbaEndpoint @splatRemoveEndpoint | Remove-DbaEndpoint -ErrorAction SilentlyContinue
        }
        if ($dbCreated) {
            $splatRemoveDb = @{
                SqlInstance = $TestConfig.InstanceHadr
                Database    = $agDbName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabase @splatRemoveDb
        }
        if ($backupDirCreated -and (Test-Path -Path $agBackupPath)) {
            $splatRemoveBackup = @{
                Path        = $agBackupPath
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatRemoveBackup
        }
    }

    Context "Against a disposable availability group" {
        It "Honors -WhatIf and does not fail over the resolved availability group" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because "no resolvable disposable availability group on InstanceHadr: $agSkipReason"
                return
            }
            $splatWhatIf = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
                WhatIf            = $true
            }
            $result = @(Invoke-DbaAgFailover @splatWhatIf)
            # The group resolves (guaranteed by the BeforeAll resolution check), so a wired gate is
            # the only reason there is no output and no Failure warning: under -WhatIf ShouldProcess
            # returns false and neither Failover nor FailoverWithPotentialDataLoss is called. A broken
            # gate would instead attempt the failover and surface a Failure warning here.
            $result.Count | Should -Be 0
            $warn -join "" | Should -Not -Match "Failure"
        }

        It "Enters the failover loop for the resolved group and contains the outcome" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because "no resolvable disposable availability group on InstanceHadr: $agSkipReason"
                return
            }
            $splatForce = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Force             = $true
                WarningVariable   = "warn"
                WarningAction     = "SilentlyContinue"
                Confirm           = $false
            }
            $result = @(Invoke-DbaAgFailover @splatForce)
            # A forced failover of the resolved group enters the per-AG loop and produces an
            # observable - the availability group object on success, or a contained Failure warning
            # when a single-replica clusterless group has no secondary to receive the failover. Either
            # way the outcome is non-terminating (EnableException is off) and never silent, which a
            # vacuous empty-loop run could not produce. The specific outcome depends on the replica
            # topology and is intentionally not pinned.
            ($result.Count + $warn.Count) | Should -BeGreaterThan 0
        }
    }
}
