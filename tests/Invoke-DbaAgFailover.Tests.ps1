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
    # a forced attempt is contained by the per-AG try/catch of the port as a non-terminating warning rather
    # than a terminating exception. Setup is probed so a non-HADR seat skips instead of failing.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $agName = "dbatoolsci_agfailover_$(Get-Random)"
        $agDbName = "dbatoolsci_agfailoverdb_$(Get-Random)"
        $agBackupPath = "$($TestConfig.Temp)\Invoke-DbaAgFailover-$(Get-Random)"

        $agReady = $false
        $agSetupError = "not attempted"
        try {
            $hadrServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr
            if (-not $hadrServer.IsHadrEnabled) {
                $agSetupError = "InstanceHadr is not HADR-enabled"
            } else {
                $null = New-Item -Path $agBackupPath -ItemType Directory
                $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceHadr -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
                $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $agDbName
                $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $agDbName -FilePath "$agBackupPath\$agDbName.bak"
                $splatNewAg = @{
                    Primary      = $TestConfig.InstanceHadr
                    Name         = $agName
                    ClusterType  = "None"
                    FailoverMode = "Manual"
                    Database     = $agDbName
                    Certificate  = "dbatoolsci_AGCert"
                }
                $null = New-DbaAvailabilityGroup @splatNewAg
                $agReady = $true
            }
        } catch {
            $agSetupError = $_.Exception.Message
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the cleanup fails loudly.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -ErrorAction SilentlyContinue
            $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring -ErrorAction SilentlyContinue | Remove-DbaEndpoint -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $agDbName -ErrorAction SilentlyContinue
        } finally {
            if (Test-Path -Path $agBackupPath) {
                Remove-Item -Path $agBackupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Against a disposable availability group" {
        It "Honors -WhatIf and does not fail over a resolved availability group" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because "no disposable availability group could be built on InstanceHadr: $agSetupError"
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
            # Under -WhatIf the inner ShouldProcess gate returns false, so neither Failover nor
            # FailoverWithPotentialDataLoss is called: no output, and no Failure warning from the catch.
            $result.Count | Should -Be 0
            $warn -join "" | Should -Not -Match "Failure"
        }

        It "Handles a forced failover of the disposable group without a terminating error" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because "no disposable availability group could be built on InstanceHadr: $agSetupError"
                return
            }
            # A single-replica clusterless AG has no synchronized secondary to receive the failover,
            # so the SMO call is expected to be rejected. The per-AG try/catch in the port (Stop-Function
            # -Continue) must contain that as a non-terminating warning exactly like the source, never
            # a terminating exception - this asserts that faithful-hop invariant, not a specific SMO
            # outcome (which depends on the replica topology). EnableException is off here, so a
            # contained failure surfaces as a warning, not a throw.
            $splatForce = @{
                SqlInstance       = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Force             = $true
                WarningAction     = "SilentlyContinue"
                Confirm           = $false
            }
            { $null = Invoke-DbaAgFailover @splatForce } | Should -Not -Throw
        }
    }
}
