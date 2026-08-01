#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaComputerSystem",
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
                "IncludeAws",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
    Context "Validate input" {
        # The mock needs -ModuleName dbatools, otherwise it never applies to the code under test and
        # the test only asserts that DNS really fails for DoesNotExist142 on the machine running it.
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName -ModuleName dbatools { $null }
            { Get-DbaComputerSystem -ComputerName "DoesNotExist142" -WarningAction Stop 3> $null } | Should -Throw -ExpectedMessage "*Unable to resolve hostname of DoesNotExist142*"
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $result = Get-DbaComputerSystem -ComputerName $TestConfig.InstanceSingle

        $props = @(
            "ComputerName",
            "Domain",
            "IsDaylightSavingsTime",
            "Manufacturer",
            "Model",
            "NumberLogicalProcessors",
            "NumberProcessors",
            "IsHyperThreading",
            "SystemFamily",
            "SystemSkuNumber",
            "SystemType",
            "IsSystemManagedPageFile",
            "TotalPhysicalMemory"
        )
    }

    Context "Validate output" {
        It "Should return all expected properties" {
            $result | Should -Not -BeNullOrEmpty
            foreach ($prop in $props) {
                $p = $result.PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }
    }
}