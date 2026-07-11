#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsConfigValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Fallback",
                "NotNull"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (W1-014): pure config-store compute, no SQL instance needed.
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $configTestName = "dbatoolsci.testvalue$(Get-Random)"
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # Test keys live only in the process-local store; no persisted state to clean.
    }

    Context "Value retrieval" {
        It "returns the configured value for a known key" {
            $result = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            $result | Should -BeOfType [int]
        }

        It "binds the key through the Name alias" {
            $viaAlias = Get-DbatoolsConfigValue -Name sql.connection.timeout
            $viaAlias | Should -Be (Get-DbatoolsConfigValue -FullName sql.connection.timeout)
        }

        It "returns the fallback for a missing key" {
            $result = Get-DbatoolsConfigValue -FullName "no.such.key.$(Get-Random)" -Fallback 42
            $result | Should -Be 42
        }

        It "returns null-shaped nothing for a missing key without fallback" {
            $result = Get-DbatoolsConfigValue -FullName "no.such.key.$(Get-Random)"
            $null -eq $result | Should -Be $true
        }

        It "coerces the string Mandatory to true" {
            Set-DbatoolsConfig -FullName $configTestName -Value "Mandatory"
            Get-DbatoolsConfigValue -FullName $configTestName | Should -Be $true
        }

        It "throws for a missing key under -NotNull regardless of EnableException" {
            # Stop-Function is called with -EnableException $true hardcoded; the message
            # interpolates the nonexistent $Name variable as empty - characterized as-is.
            { Get-DbatoolsConfigValue -FullName "no.such.key.$(Get-Random)" -NotNull } | Should -Throw
        }
    }
}