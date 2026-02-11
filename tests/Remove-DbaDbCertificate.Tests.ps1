#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbCertificate",
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
                "Certificate",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can remove a database certificate" {
        It "Successfully removes database certificate in master" {
            # Create and then remove a database certificate for testing
            $results = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle | Remove-DbaDbCertificate

            "$($results.Status)" -match "Success" | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $outputCertName = "dbatoolsci_certout_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Name $outputCertName -Database master
            $result = Remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master -Certificate $outputCertName -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the correct properties" {
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Certificate", "Status")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the expected values" {
            $result.Status | Should -Be "Success"
            $result.Database | Should -Be "master"
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Certificate | Should -Not -BeNullOrEmpty
        }
    }
}