#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceList",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            # $TestConfig.CommonParameters is a HashSet, which Compare-Object treats as a single
            # object. Every other test file gets away with the bare property because the "+= @()"
            # on the next line converts it to an array first. This command has no parameters of
            # its own, so there is no "+=" and the conversion has to happen here.
            $expectedParameters = @($TestConfig.CommonParameters)
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $instanceName = "dbatoolsci_testinstance_$(Get-Random)"
        Add-DbaInstanceList -SqlInstance $instanceName
    }

    AfterAll {
        $null = Remove-DbaInstanceList -SqlInstance $instanceName -ErrorAction SilentlyContinue
    }

    Context "returns the instance list" {
        It "returns results without error" {
            { Get-DbaInstanceList } | Should -Not -Throw
        }

        It "returns the added instance" {
            $result = Get-DbaInstanceList
            $result | Should -Contain $instanceName.ToLowerInvariant()
        }
    }
}
