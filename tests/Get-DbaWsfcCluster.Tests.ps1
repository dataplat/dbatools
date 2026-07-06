#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcCluster",
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
    # Characterization tests (2026-07-06, Track A): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name and
    # reaches a WSFC member node; reading root\MSCluster over CIM requires the runner to
    # hold local admin on the member nodes (the lab gate runner has that via full logon).
    Context "When querying the lab failover cluster" {
        BeforeAll {
            $clusterResults = @(Get-DbaWsfcCluster -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns exactly one cluster object" {
            $clusterResults.Count | Should -Be 1
        }

        It "Returns the MSCluster_Cluster CIM instance" {
            $clusterResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_Cluster"
        }

        It "Reports cluster identity and quorum configuration" {
            $clusterResults[0].Name | Should -Not -BeNullOrEmpty
            $clusterResults[0].Fqdn | Should -Match "^$([regex]::Escape($clusterResults[0].Name))\."
            $clusterResults[0].QuorumType | Should -Not -BeNullOrEmpty
            $clusterResults[0].QuorumTypeValue | Should -BeGreaterOrEqual 0
        }

        It "Carries the State note property as null" {
            # The live implementation computes State from an undefined variable
            # (Get-ResourceState $resource.State), so the note property is always
            # added with a null value. Pinned so the port reproduces it verbatim.
            $stateProperty = $clusterResults[0].PSObject.Properties["State"]
            $stateProperty | Should -Not -BeNullOrEmpty
            $stateProperty.MemberType | Should -Be "NoteProperty"
            $stateProperty.Value | Should -BeNullOrEmpty
        }

        It "Accepts pipeline input" {
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcCluster)
            $pipelineResults.Count | Should -Be 1
            $pipelineResults[0].Name | Should -Be $clusterResults[0].Name
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns instead of throwing, even with EnableException" {
            # EnableException is never forwarded to the inner CIM lookup, so connection
            # failures always surface as a warning and the computer is skipped.
            $unreachableResults = Get-DbaWsfcCluster -ComputerName "dbatoolsci_nohost" -EnableException -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $unreachableResults | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
