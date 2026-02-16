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
    }

    Context "Output validation" {
        BeforeAll {
            $splatEncryption = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = "master"
                EnableException  = $true
            }
            $global:dbatoolsciOutput = @(Get-DbaDbEncryption @splatEncryption)
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Encryption",
                "Name",
                "LastBackup",
                "PrivateKeyEncryptionType",
                "EncryptionAlgorithm",
                "KeyLength",
                "Owner",
                "Object",
                "ExpirationDate"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}