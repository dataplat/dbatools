#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCategory",
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
                "Category",
                "InputObject",
                "ExcludeSystemObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

if ($PSVersionTable.PSEdition -ne "Core") {
    Describe $CommandName -Tag IntegrationTests {
    # Skip IntegrationTests on pwsh because working with policies is not supported.

    Context "Command actually works" {
        It "Gets Results" {
            $results = Get-DbaPbmCategory -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -Category" {
        It "Gets Results" {
            $results = Get-DbaPbmCategory -SqlInstance $TestConfig.InstanceSingle -Category "Availability database errors"
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -ExcludeSystemObject" {
        It "Gets Results" {
            $results = Get-DbaPbmCategory -SqlInstance $TestConfig.InstanceSingle -ExcludeSystemObject
            $results | Should -Not -BeNullOrEmpty
        }
    }
    }
} else {
    Describe $CommandName -Tag IntegrationTests {
        Context "Guarding on PowerShell Core" {
            It "Warns and returns nothing on PowerShell Core" {
                $result = @(Get-DbaPbmCategory -SqlInstance "dbatoolsci-core-guard" -WarningVariable warn -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                $payloads = @($warn | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" })
                $payloads | Should -Contain "This command is not supported on Linux or macOS"
            }
        }
    }
}
