#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcSharedVolume",
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

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Characterization tests (2026-07-07, Track A TA-074): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-07): the lab WSFC (wincluster) has NO Cluster Shared Volumes (CSVs).
    # CSVs are used for Hyper-V/SOFS clusters; a pure SQL FCI uses dedicated disk resources, not
    # CSVs. ClusterSharedVolume WMI class exists in root\MSCluster but has 0 instances.
    # ClusterName="wincluster", ClusterFqdn="wincluster.lab.local" (from Get-DbaWsfcCluster).
    #
    # Source code note: the function has a bug on the State add-member line: it calls
    # Get-ResourceState $resource.State but the loop variable is $volume (not $resource),
    # so State is always $null on any returned volume. This bug cannot be triggered in the lab
    # because no CSVs exist, but it is documented here as a characterization note for the C# port.
    # characterization: State variable bug -- do not "fix" without a surface-diff decision.
    Context "When querying a WSFC cluster with no Cluster Shared Volumes" {
        BeforeAll {
            # No fixture setup -- read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $csvResults = @(Get-DbaWsfcSharedVolume -ComputerName $TestConfig.InstanceMulti2 -WarningVariable warnConnected -WarningAction SilentlyContinue)
        }

        It "Returns an empty collection when no CSVs are configured on the cluster" {
            # characterization: the lab WSFC (wincluster) has no CSVs; the CIM class exists
            # but has zero instances -- the command returns nothing, not an error
            $csvResults.Count | Should -Be 0
        }

        It "Emits no warnings when successfully querying a cluster with no CSVs" {
            # characterization: an empty CIM result set is not an error condition;
            # no warnings are produced when the connection succeeds but returns nothing
            "$warnConnected" | Should -BeNullOrEmpty
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $directResults = @(Get-DbaWsfcSharedVolume -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Accepts pipeline input and returns the same count as direct call" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcSharedVolume)
            $pipelineResults.Count | Should -Be $directResults.Count
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcSharedVolume calls Get-DbaWsfcCluster then Get-DbaCmObject.
            # When neither can connect, both inner helpers emit warnings and return empty;
            # the outer command produces no output.
            $splatBad = @{
                ComputerName    = "dbatoolsci_nohost"
                WarningVariable = "warnBad"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $unreachableResult = Get-DbaWsfcSharedVolume @splatBad
            $unreachableResult | Should -BeNullOrEmpty
            "$warnBad" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
