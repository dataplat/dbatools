#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaDbEncryption",
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
                "EncryptorName",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master |
            Where-Object Name -notmatch "##" |
            Select-Object -First 1

        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $testDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $testDb | New-DbaDbMasterKey -SecurePassword $passwd
        $testDb | New-DbaDbCertificate
        $testDb | New-DbaDbEncryptionKey -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($testDb) {
            $testDb | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When enabling encryption via pipeline" {
        It "Should enable encryption on a database" {
            $results = @($testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force)
            $results[0].EncryptionEnabled | Should -Be $true
        }
    }

    Context "When enabling encryption directly" {
        It "Should enable encryption on a database" {
            $null = Disable-DbaDbEncryption -SqlInstance $TestConfig.InstanceSingle -Database $testDb.Name
            $splatEnableEncryption = @{
                SqlInstance   = $TestConfig.InstanceSingle
                EncryptorName = $mastercert.Name
                Database      = $testDb.Name
                Force         = $true
            }
            $results = @(Enable-DbaDbEncryption @splatEnableEncryption)
            $results[0].EncryptionEnabled | Should -Be $true
        }
    }

}

Describe "$CommandName Output" -Tag IntegrationTests {
    BeforeAll {
        $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $outputMastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master |
            Where-Object Name -notmatch "##" |
            Select-Object -First 1

        if (-not $outputMastercert) {
            $outputDelMastercert = $true
            $outputMasterKey = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database master
            if (-not $outputMasterKey) {
                $outputDelMasterKey = $true
                $outputServer.Query("CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'dbatools.IO'", "master")
            }
            $outputServer.Query("CREATE CERTIFICATE dbatoolsci_enc_outputcert WITH SUBJECT = 'Output Test Cert'", "master")
            $outputCertName = "dbatoolsci_enc_outputcert"
        } else {
            $outputCertName = $outputMastercert.Name
        }

        $outputDbName = "dbatoolsci_enc_output"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDbName
        $outputServer.Query("CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'dbatools.IO'", $outputDbName)
        $outputServer.Query("CREATE CERTIFICATE dbatoolsci_enc_outputdbcert WITH SUBJECT = 'DB Output Cert'", $outputDbName)
        $outputServer.Query("CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE $outputCertName", $outputDbName)

        $splatOutputEncryption = @{
            SqlInstance   = $TestConfig.InstanceSingle
            EncryptorName = $outputCertName
            Database      = $outputDbName
            Force         = $true
            Confirm       = $false
        }
        $outputResult = @(Enable-DbaDbEncryption @splatOutputEncryption)
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Confirm:$false -ErrorAction SilentlyContinue
        if ($outputDelMastercert) {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "DROP CERTIFICATE dbatoolsci_enc_outputcert" -ErrorAction SilentlyContinue
        }
        if ($outputDelMasterKey) {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "DROP MASTER KEY" -ErrorAction SilentlyContinue
        }
    }

    Context "Output validation" {
        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Database"
        }

        It "Has the expected default display properties" {
            $outputResult | Should -Not -BeNullOrEmpty
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "EncryptionEnabled")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.Properties["DatabaseName"] | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.Properties["DatabaseName"].MemberType | Should -Be "AliasProperty"
        }
    }
}