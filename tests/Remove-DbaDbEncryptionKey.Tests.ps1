#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbEncryptionKey",
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
                "InputObject",
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

        $encryptionPasswd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $masterCertExists = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $masterCertExists) {
            $delmastercert = $true
            $masterCertExists = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $testDatabase = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $testDatabase | New-DbaDbMasterKey -SecurePassword $encryptionPasswd
        $testDatabase | New-DbaDbCertificate
        $testDbEncryptionKey = $testDatabase | New-DbaDbEncryptionKey -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($testDatabase) {
            $testDatabase | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $masterCertExists | Remove-DbaDbCertificate
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should remove encryption key on a database using piping" {
            $results = $testDbEncryptionKey | Remove-DbaDbEncryptionKey
            $results.Status | Should -Be "Success"
            $testDatabase.Refresh()
            $testDatabase | Get-DbaDbEncryptionKey | Should -Be $null
        }
        It "should remove encryption key on a database" {
            $null = $testDatabase | New-DbaDbEncryptionKey -Force
            $results = Remove-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $testDatabase.Name
            $results.Status | Should -Be "Success"
            $testDatabase.Refresh()
            $testDatabase | Get-DbaDbEncryptionKey | Should -Be $null
        }
    }

}

Describe "$CommandName Output" -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $outputEncPasswd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $outputMasterCertName = "dbatoolsci_enckeyout_$(Get-Random)"
            $outputMasterCert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $outputMasterCert) {
                $deleteOutputMasterCert = $true
                $outputMasterCert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Name $outputMasterCertName -Database master -EnableException
            }

            $outputEncDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -EnableException
            $outputEncDb | New-DbaDbMasterKey -SecurePassword $outputEncPasswd -Confirm:$false -EnableException
            $outputEncDb | New-DbaDbCertificate -EnableException
            $null = $outputEncDb | New-DbaDbEncryptionKey -EncryptorName $outputMasterCert.Name -Force -EnableException
            $result = Remove-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $outputEncDb.Name -Confirm:$false -EnableException
        }

        AfterAll {
            if ($outputEncDb) {
                $outputEncDb | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
            }
            if ($deleteOutputMasterCert) {
                Remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master -Certificate $outputMasterCertName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the correct properties" {
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Status")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the expected values" {
            $result.Status | Should -Be "Success"
            $result.Database | Should -Be $outputEncDb.Name
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}