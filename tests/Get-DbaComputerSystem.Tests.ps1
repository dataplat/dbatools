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
# P0-008 message-channel proof (BP-6xx gate, specs/best-practices.md): a NATIVELY implemented
# binary cmdlet whose warning originates in WriteMessage(MessageLevel.Warning, ...) must surface
# that warning through the caller's -WarningVariable on BOTH editions. Get-DbaComputerSystem is a
# flipped dbatools.computer cmdlet; a bogus ComputerName fails name resolution inside the C#
# NetworkResolutionService, and without EnableException the cmdlet calls WriteMessage(Warning,
# "DNS name ... not found") and continues (GetDbaComputerSystemCommand.cs:68,72). Offline by
# design - no lab computer is contacted - so the channel binding, not connectivity, is what is
# under test. The gate runs this Describe under -Tag IntegrationTests on pwsh and powershell.exe.
Describe "$CommandName message channel (P0-008)" -Tag IntegrationTests {
    It "surfaces a WriteMessage warning through -WarningVariable on this edition (native cmdlet)" {
        (Get-Command $CommandName).CommandType | Should -Be "Cmdlet"
        $warn = $null
        $null = Get-DbaComputerSystem -ComputerName "p0008-no-such-host-doesnotexist.invalid" -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -Not -BeNullOrEmpty
        "$warn" | Should -Match "not found"
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