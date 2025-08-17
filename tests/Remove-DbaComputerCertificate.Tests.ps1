#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaComputerCertificate",
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
                "Thumbprint",
                "Store",
                "Folder",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can remove a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt" -Confirm:$false
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
            $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
        }

        It "returns the store Name" {
            $results.Store -eq "LocalMachine" | Should -Be $true
        }

        It "returns the folder Name" {
            $results.Folder -eq "My" | Should -Be $true
        }

        It "reports the proper status of Removed" {
            $results.Status -eq "Removed" | Should -Be $true
        }

        It "really removed it" {
            $verifyResults = Get-DbaComputerCertificate -Thumbprint $thumbprint
            $verifyResults | Should -BeNullOrEmpty
        }
    }
}