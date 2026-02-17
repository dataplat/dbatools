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
    BeforeAll {
        $null = New-DbaCmConnection -ComputerName $env:COMPUTERNAME
    }

    AfterAll {
        Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -ErrorAction SilentlyContinue
    }

    Context "When setting connection properties" {
        It "Should return a connection object" {
            $result = Set-DbaCmConnection -ComputerName $env:COMPUTERNAME -ResetConfiguration -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Dataplat.Dbatools.Connection.ManagementConnection]
        }

        It "Should have a ComputerName property" {
            $global:dbatoolsciOutput[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Dataplat\.Dbatools\.Connection\.ManagementConnection"
        }
    }
}