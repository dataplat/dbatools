#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "First",
                "Last",
                "Skip",
                "All"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets an error" {
        It "returns a dbatools error" {
            try {
                $null = Connect-DbaInstance -SqlInstance "nothing" -ConnectTimeout 1 -ErrorAction Stop
            } catch { }
            Get-DbatoolsError | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            try {
                $null = Connect-DbaInstance -SqlInstance "dbatoolsci_fakeinst" -ConnectTimeout 1 -ErrorAction Stop
            } catch { }
            $result = Get-DbatoolsError -First 1
        }

        It "Returns output with expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @(
                "CategoryInfo",
                "ErrorDetails",
                "Exception",
                "FullyQualifiedErrorId",
                "InvocationInfo",
                "PipelineIterationInfo",
                "PSMessageDetails",
                "ScriptStackTrace",
                "TargetObject"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has a dbatools FullyQualifiedErrorId" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].FullyQualifiedErrorId | Should -Match "dbatools"
        }
    }
}