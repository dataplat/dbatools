#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaBuildReference",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        $global:TestConfig = Get-TestConfig
    }

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
    Context "Function behavior" {
        BeforeAll {
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