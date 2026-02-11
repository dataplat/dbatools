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

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not (Get-CimInstance -Namespace root\MSCluster -ClassName MSCluster_Cluster -ErrorAction SilentlyContinue)) {
        BeforeAll {
            $result = Get-DbaWsfcSharedVolume
        }

        It "Has the expected added NoteProperties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["ClusterName"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["ClusterFqdn"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["State"] | Should -Not -BeNullOrEmpty
        }
    }
}