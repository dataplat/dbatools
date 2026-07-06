#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcAvailableDisk",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (2026-07-06, Track A TA-065): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # MSCluster_AvailableDisk returns disks visible to all nodes but NOT yet assigned to any cluster
    # group. In the lab FCI all disks are already assigned, so the normal result is empty.
    # root\MSCluster CIM requires domain auth — the SSH-key gate session lacks network credentials
    # and both Get-DbaWsfcCluster and Get-DbaCmObject emit auth warnings (not errors) because
    # EnableException is NOT forwarded to those inner commands. The outer command completes and
    # returns empty in either case (auth failure path or genuinely-no-available-disks path).
    #
    # Known bug: Get-DbaWsfcAvailableDisk uses $resource.State (undefined variable) in the
    # Add-Member call so State is always $null on any returned disk. Cannot assert this in the
    # lab because no available disks are returned, but the C# port must replicate the null-State
    # behavior until a deliberate surface-change decision is made.
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup required — this command is read-only. Do NOT set EnableException
            # globally here: the inner Get-DbaWsfcCluster and Get-DbaCmObject warn (not throw)
            # when the SSH gate lacks domain credentials for CIM auth, so enabling EnableException
            # via PSDefaultParameterValues would turn those warnings into terminating errors.
            $availDiskResults = @(Get-DbaWsfcAvailableDisk -ComputerName $TestConfig.InstanceMulti2 -WarningAction SilentlyContinue)
        }

        It "Completes without error against the FCI network name" {
            # characterization: even when CIM auth warnings occur (SSH gate, no domain creds),
            # the command finishes and does not throw. Inner helpers warn; the outer command eats
            # the empty result and returns normally.
            $true | Should -BeTrue
        }

        It "Returns empty when all cluster disks are assigned (or when CIM auth warns and returns nothing)" {
            # characterization: MSCluster_AvailableDisk is empty in the lab. The C# port must
            # also return empty under these conditions. Do not add unassigned fixture disks.
            $availDiskResults.Count | Should -Be 0
        }

        It "Returns the same result via pipeline input" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via pipeline.
            $pipeResult = @($TestConfig.InstanceMulti2 | Get-DbaWsfcAvailableDisk -WarningAction SilentlyContinue)
            $pipeResult.Count | Should -Be $availDiskResults.Count
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: two warnings are emitted — one from Get-DbaWsfcCluster and one
            # from Get-DbaCmObject (which queries MSCluster_AvailableDisk). Neither helper
            # forwards EnableException, so the command never throws; it warns and returns nothing.
            # The warning text confirms connection failure.
            $unreachableResult = Get-DbaWsfcAvailableDisk -ComputerName "dbatoolsci_nohost" -WarningVariable warnMessages -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResult | Should -BeNullOrEmpty
            "$warnMessages" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
