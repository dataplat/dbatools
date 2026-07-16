#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "UseWindowsCredentials",
                "OverrideExplicitCredential",
                "OverrideConnectionPolicy",
                "DisabledConnectionTypes",
                "DisableBadCredentialCache",
                "DisableCimPersistence",
                "DisableCredentialAutoRegister",
                "EnableCredentialFailover",
                "WindowsCredentialsAreBad",
                "CimWinRMOptions",
                "CimDCOMOptions",
                "AddBadCredential",
                "RemoveBadCredential",
                "ClearBadCredential",
                "ClearCredential",
                "ResetCredential",
                "ResetConnectionStatus",
                "ResetConfiguration",
                "EnableException"
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
    # Characterization context (W1-094 law: an empty run is never green). The CIM connection
    # cache is process-local state - no lab instance required (W3-063/071 sibling pattern).
    Context "When updating a registered connection" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = New-DbaCmConnection -ComputerName dbatoolsci-w3087
            $setResults = @(Set-DbaCmConnection -ComputerName dbatoolsci-w3087 -DisableBadCredentialCache)
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaCmConnection -ComputerName dbatoolsci-w3087 -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the updated connection with the bad-credential cache disabled" {
            $setResults.Count | Should -Be 1
            $setResults[0].DisableBadCredentialCache | Should -BeTrue
        }
    }
}
