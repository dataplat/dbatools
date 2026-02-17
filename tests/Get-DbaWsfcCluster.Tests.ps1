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

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $results = Get-DbaWsfcCluster -ComputerName $TestConfig.InstanceHadr -WarningVariable WarnVar -OutVariable "global:dbatoolsciOutput"
    }

    Context "Validate output" {
        It "Should return cluster information without errors" {
            $WarnVar | Should -BeNullOrEmpty
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a cluster name" {
            $results[0].Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
        }

        It "Should have the correct default display columns" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $expectedColumns = @(
                "Name",
                "Fqdn",
                "State",
                "DrainOnShutdown",
                "DynamicQuorumEnabled",
                "EnableSharedVolumes",
                "SharedVolumesRoot",
                "QuorumPath",
                "QuorumType",
                "QuorumTypeValue",
                "RequestReplyTimeout"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have the added State property" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "State"
        }

        It "Should have a non-empty Name property" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0].Name | Should -Not -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "MSCluster_Cluster"
        }
    }
}