#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-SqlDefaultSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        $global:TestConfig = Get-TestConfig
        . "$PSScriptRoot\..\private\functions\Get-SqlDefaultSPConfigure.ps1"
        
        $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
        $expectedParameters = $TestConfig.CommonParameters
        $expectedParameters += @(
            "SqlVersion"
        )
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Try all versions of SQL" {
        BeforeAll {
            $versionName = @{
                8  = "2000"
                9  = "2005"
                10 = "2008/2008R2"
                11 = "2012"
                12 = "2014"
                13 = "2016"
                14 = "2017"
                15 = "2019"
                16 = "2022"
            }
        }

        It "Should return results for SQL Server 2000 (version 8)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 8
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Should return results for SQL Server 2005 (version 9)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 9
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Should return results for SQL Server 2008/2008R2 (version 10)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 10
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Should return results for SQL Server 2012 (version 11)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 11
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Should return results for SQL Server 2014 (version 12)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 12
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Should return results for SQL Server 2016 (version 13)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 13
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }

        It "Should return results for SQL Server 2017 (version 14)" {
            $results = Get-SqlDefaultSPConfigure -SqlVersion 14
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }
    }
}