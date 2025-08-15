#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccHelp",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Statement",
                "IncludeUndocumented",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $props = @("Operation", "Cmd", "Output")
        $result = Get-DbaDbccHelp -SqlInstance $TestConfig.instance2 -Statement FREESYSTEMCACHE
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
    }

    Context "Works correctly" {
        It "returns the right results for FREESYSTEMCACHE" {
            $result.Operation | Should -Be "FREESYSTEMCACHE"
            $result.Cmd | Should -Be "DBCC HELP(FREESYSTEMCACHE)"
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "returns the right results for PAGE" {
            $pageResult = Get-DbaDbccHelp -SqlInstance $TestConfig.instance2 -Statement PAGE -IncludeUndocumented
            $pageResult.Operation | Should -Be "PAGE"
            $pageResult.Cmd | Should -Be "DBCC HELP(PAGE)"
            $pageResult.Output | Should -Not -BeNullOrEmpty
        }
    }
}