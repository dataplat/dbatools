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
        $result = Get-DbaDbccHelp -SqlInstance $TestConfig.InstanceSingle -Statement FREESYSTEMCACHE
    }

    Context "Validate standard output" {
        It "Should return property: Operation" {
            $result.PSObject.Properties["Operation"].Name | Should -Be "Operation"
        }

        It "Should return property: Cmd" {
            $result.PSObject.Properties["Cmd"].Name | Should -Be "Cmd"
        }

        It "Should return property: Output" {
            $result.PSObject.Properties["Output"].Name | Should -Be "Output"
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProperties = @("Operation", "Cmd", "Output")
            foreach ($prop in $expectedProperties) {
                $result[0].psobject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist"
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