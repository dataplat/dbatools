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

    Context "Output Validation" {
        BeforeAll {
            $random = Get-Random
            $cert = "dbatoolsci_output$random"
            $password = ConvertTo-SecureString -String Get-Random -AsPlainText -Force

            $splatCertificate = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $cert
                Password    = $password
            }
            New-DbaDbCertificate @splatCertificate

            $result = Get-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException
        }

        AfterAll {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceSingle
                Certificate = $cert
            }
            Get-DbaDbCertificate @splatRemove | Remove-DbaDbCertificate
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected common properties for all encryption types" {
            $expectedCommonProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Encryption',
                'Name',
                'Owner',
                'Object'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedCommonProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in all encryption objects"
            }
        }

        It "Has the expected type-specific properties" {
            $expectedTypeProps = @(
                'LastBackup',
                'PrivateKeyEncryptionType',
                'EncryptionAlgorithm',
                'KeyLength',
                'ExpirationDate'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedTypeProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available for encryption objects"
            }
        }

        It "Returns certificate objects with expected properties populated" {
            $certResult = $result | Where-Object { $_.Encryption -eq 'Certificate' -and $_.Name -eq $cert }
            $certResult | Should -Not -BeNullOrEmpty
            $certResult.ComputerName | Should -Not -BeNullOrEmpty
            $certResult.InstanceName | Should -Not -BeNullOrEmpty
            $certResult.SqlInstance | Should -Not -BeNullOrEmpty
            $certResult.Database | Should -Be 'master'
            $certResult.Name | Should -Be $cert
        }
    }
}