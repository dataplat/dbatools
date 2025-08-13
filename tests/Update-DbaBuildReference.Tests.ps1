#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Update-DbaBuildReference",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        $global:TestConfig = Get-TestConfig
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = $TestConfig.CommonParameters
        $expectedParameters += @(
            "LocalFile",
            "EnableException"
        )
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    Context "Function behavior" {
        BeforeAll {
            # Setup mock function for testing
            function Get-DbaBuildReferenceIndexOnline { }
        }

        It "calls the internal function" {
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { } -ModuleName dbatools
            { Update-DbaBuildReference -EnableException -ErrorAction Stop } | Should -Not -Throw
        }

        It "errors out when cannot download" {
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { throw "cannot download" } -ModuleName dbatools
            { Update-DbaBuildReference -EnableException -ErrorAction Stop } | Should -Throw
        }
    }
}