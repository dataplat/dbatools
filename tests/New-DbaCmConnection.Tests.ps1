#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaCmConnection",
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
                "DisabledConnectionTypes",
                "DisableBadCredentialCache",
                "DisableCimPersistence",
                "DisableCredentialAutoRegister",
                "EnableCredentialFailover",
                "WindowsCredentialsAreBad",
                "CimWinRMOptions",
                "CimDCOMOptions",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "When creating a connection" {
        BeforeAll {
            $cmConnectionResult = New-DbaCmConnection -ComputerName $env:COMPUTERNAME -UseWindowsCredentials -OutVariable "global:dbatoolsciOutput"
        }

        AfterAll {
            Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -ErrorAction SilentlyContinue
        }

        It "Should return a connection object" {
            $cmConnectionResult | Should -Not -BeNullOrEmpty
        }

        It "Should have the correct computer name" {
            $cmConnectionResult.ComputerName | Should -Be $env:COMPUTERNAME
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