#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbLogShipStatus",
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
                "Database",
                "ExcludeDatabase",
                "Simple",
                "Primary",
                "Secondary",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When testing SQL instance edition support" {
        It -Skip:(-not $TestConfig.InstanceExpress) "Should warn if SQL instance edition is not supported" {
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceExpress -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Express"
        }
    }

    Context "When no log shipping is configured" {
        It "Should warn if no log shipping found" {
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceSingle -Database 'master' -WarningAction SilentlyContinue
            $WarnVar | Should -Match "No information available"
        }
    }

    Context "Output validation" {
        It "Returns no output when log shipping is not configured" {
            $result = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}