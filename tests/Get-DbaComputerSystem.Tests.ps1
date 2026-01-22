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
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName { $null }
            { Get-DbaComputerSystem -ComputerName "DoesNotExist142" -WarningAction Stop 3> $null } | Should -Throw
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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaComputerSystem -ComputerName $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "Domain",
                "DomainRole",
                "Manufacturer",
                "Model",
                "SystemFamily",
                "SystemType",
                "ProcessorName",
                "ProcessorCaption",
                "ProcessorMaxClockSpeed",
                "NumberLogicalProcessors",
                "NumberProcessors",
                "IsHyperThreading",
                "TotalPhysicalMemory",
                "IsSystemManagedPageFile",
                "PendingReboot"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties not shown by default" {
            $additionalProps = @(
                "SystemSkuNumber",
                "IsDaylightSavingsTime",
                "DaylightInEffect",
                "DnsHostName",
                "AdminPasswordStatus"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available via Select-Object *"
            }
        }
    }

    Context "Output with -IncludeAws" {
        BeforeAll {
            # Note: This test will only add AWS properties if the target is actually an EC2 instance
            # On non-AWS systems, these properties won't be added
            $result = Get-DbaComputerSystem -ComputerName $TestConfig.InstanceSingle -IncludeAws -EnableException
        }

        It "Includes AWS properties when detected as EC2 instance" {
            # AWS properties are conditionally added only if the system is detected as an EC2 instance
            # We test that the command executes successfully with -IncludeAws
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain "ComputerName"
        }
    }
}