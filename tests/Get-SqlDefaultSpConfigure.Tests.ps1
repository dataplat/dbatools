#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-SqlDefaultSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlVersion"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Try all versions of SQL" {
        BeforeDiscovery {
            # -ForEach is read while Pester discovers the tests, so the case list holds data only.
            # It used to be built in the BeforeAll below by calling the function under test, which
            # meant it was still empty at discovery and neither of these tests existed at all.
            # The function is dot sourced in BeforeAll and called inside the It, which runs later.
            $versionCase = @(
                @{ Version = 8; VersionName = "2000" }
                @{ Version = 9; VersionName = "2005" }
                @{ Version = 10; VersionName = "2008/2008R2" }
                @{ Version = 11; VersionName = "2012" }
                @{ Version = 12; VersionName = "2014" }
                @{ Version = 13; VersionName = "2016" }
                @{ Version = 14; VersionName = "2017" }
            )
        }

        BeforeAll {
            . "$PSScriptRoot\..\private\functions\Get-SqlDefaultSPConfigure.ps1"
        }

        It "Should return results for <VersionName>" -ForEach $versionCase {
            $results = Get-SqlDefaultSPConfigure -SqlVersion $Version
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return 'System.Management.Automation.PSCustomObject' object for <VersionName>" -ForEach $versionCase {
            $results = Get-SqlDefaultSPConfigure -SqlVersion $Version
            $results.GetType().fullname | Should -Be "System.Management.Automation.PSCustomObject"
        }
    }
}
