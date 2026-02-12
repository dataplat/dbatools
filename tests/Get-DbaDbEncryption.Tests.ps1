#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbEncryption",
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
                "IncludeSystemDBs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Test Retriving Certificate" {
        BeforeAll {
            $random = Get-Random
            $cert = "dbatoolsci_getcert$random"
            $password = ConvertTo-SecureString -String Get-Random -AsPlainText -Force

            $splatCertificate = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $cert
                Password    = $password
            }
            New-DbaDbCertificate @splatCertificate

            $results = Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle

            # Store results for output validation
            $script:outputResults = Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -IncludeSystemDBs
        }

        AfterAll {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceSingle
                Certificate = $cert
            }
            Get-DbaDbCertificate @splatRemove | Remove-DbaDbCertificate
        }

        It "Should find a certificate named $cert" {
            ($results.Name -match "dbatoolsci").Count -gt 0 | Should -Be $true
        }

        It "Returns output as PSCustomObject" {
            if (-not $script:outputResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:outputResults[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected common properties" {
            if (-not $script:outputResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Encryption", "Name", "Owner", "Object")
            foreach ($prop in $expectedProperties) {
                $script:outputResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the expected encryption-specific properties" {
            if (-not $script:outputResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $encryptionProperties = @("LastBackup", "PrivateKeyEncryptionType", "EncryptionAlgorithm", "KeyLength", "ExpirationDate")
            foreach ($prop in $encryptionProperties) {
                $script:outputResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}