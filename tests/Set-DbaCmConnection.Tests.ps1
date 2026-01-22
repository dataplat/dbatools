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

    Context "Output Validation" {
        BeforeAll {
            $result = Set-DbaCmConnection -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Dataplat.Dbatools.Connection.ManagementConnection]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'IsConnected',
                'CimRM',
                'CimDCOM',
                'Wmi',
                'PowerShellRemoting'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional documented properties available" {
            $additionalProps = @(
                'Credentials',
                'UseWindowsCredentials',
                'WindowsCredentialsAreBad',
                'KnownBadCredentials',
                'OverrideExplicitCredential',
                'OverrideConnectionPolicy',
                'DisabledConnectionTypes',
                'DisableBadCredentialCache',
                'DisableCimPersistence',
                'DisableCredentialAutoRegister',
                'EnableCredentialFailover',
                'CimWinRMOptions',
                'CimDCOMOptions'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>