#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCertificate",
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
                "Certificate",
                "Subject",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can get a database certificate" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"
            $dbName = "dbatoolscli_db1_$(Get-Random)"
            $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Password $pw

            $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Password $pw -Name $certificateName1
            $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Password $pw -Name $certificateName2

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns database certificate by certificate name" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Certificate $certificateName1
            $cert.Database | Should -Match $dbName
            $cert.Name | Should -Match $certificateName1
        }

        It "Returns database certificates by database name" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $cert | Should -HaveCount 2
            $cert.Name | Should -BeIn $certificateName1, $certificateName2
        }

        It "Returns database certificates excluding those in the test database" {
            $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbName
            $cert.Database | Should -Not -Match $dbName
            $cert.Name | Should -Not -BeIn $certificateName1, $certificateName2
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $certificateName = "Cert_$(Get-Random)"
            $dbName = "dbatoolscli_db2_$(Get-Random)"
            $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Password $pw
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Password $pw -Name $certificateName

            $result = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database $dbName -EnableException

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Certificate]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Name',
                'Subject',
                'StartDate',
                'ActiveForServiceBrokerDialog',
                'ExpirationDate',
                'Issuer',
                'LastBackupDate',
                'Owner',
                'PrivateKeyEncryptionType',
                'Serial'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected added context properties" {
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName' -Because 'dbatools adds ComputerName via Add-Member'
            $result.PSObject.Properties.Name | Should -Contain 'InstanceName' -Because 'dbatools adds InstanceName via Add-Member'
            $result.PSObject.Properties.Name | Should -Contain 'SqlInstance' -Because 'dbatools adds SqlInstance via Add-Member'
            $result.PSObject.Properties.Name | Should -Contain 'Database' -Because 'dbatools adds Database via Add-Member'
            $result.PSObject.Properties.Name | Should -Contain 'DatabaseId' -Because 'dbatools adds DatabaseId via Add-Member'
        }
    }
}