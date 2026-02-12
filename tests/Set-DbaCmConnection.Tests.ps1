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
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = Set-DbaCmConnection -ComputerName $env:COMPUTERNAME -ResetConfiguration
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Connection.ManagementConnection"
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties.Name | Should -Contain "ComputerName"
            $result[0].psobject.Properties.Name | Should -Contain "CimRM"
            $result[0].psobject.Properties.Name | Should -Contain "CimDCOM"
            $result[0].psobject.Properties.Name | Should -Contain "Wmi"
            $result[0].psobject.Properties.Name | Should -Contain "PowerShellRemoting"
            $result[0].psobject.Properties.Name | Should -Contain "DisabledConnectionTypes"
            $result[0].psobject.Properties.Name | Should -Contain "OverrideExplicitCredential"
        }
    }
}