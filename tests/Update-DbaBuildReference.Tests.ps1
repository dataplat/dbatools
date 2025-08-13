#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Update-DbaBuildReference",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "LocalFile",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    Context "Internal function calls" {
        It "calls the internal function" {
            function Get-DbaBuildReferenceIndexOnline { }
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { } -ModuleName dbatools
            { Update-DbaBuildReference -EnableException -ErrorAction Stop } | Should -Not -Throw
        }

        It "errors out when cannot download" {
            function Get-DbaBuildReferenceIndexOnline { }
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { throw "cannot download" } -ModuleName dbatools
            { Update-DbaBuildReference -EnableException -ErrorAction Stop } | Should -Throw
        }
    }
}