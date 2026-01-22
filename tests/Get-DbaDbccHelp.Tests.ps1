#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccHelp",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Statement",
                "IncludeUndocumented",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $props = @("Operation", "Cmd", "Output")
        $result = Get-DbaDbccHelp -SqlInstance $TestConfig.InstanceSingle -Statement FREESYSTEMCACHE -EnableException
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "Operation",
                "Cmd",
                "Output"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Works correctly" {
        It "returns the right results for FREESYSTEMCACHE" {
            $result.Operation | Should -Be "FREESYSTEMCACHE"
            $result.Cmd | Should -Be "DBCC HELP(FREESYSTEMCACHE)"
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "returns the right results for PAGE" {
            $pageResult = Get-DbaDbccHelp -SqlInstance $TestConfig.InstanceSingle -Statement PAGE -IncludeUndocumented
            $pageResult.Operation | Should -Be "PAGE"
            $pageResult.Cmd | Should -Be "DBCC HELP(PAGE)"
            $pageResult.Output | Should -Not -BeNullOrEmpty
        }
    }
}