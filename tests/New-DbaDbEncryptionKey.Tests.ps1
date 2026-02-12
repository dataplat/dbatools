#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbEncryptionKey",
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
                "EnableException",
                "EncryptorName",
                "EncryptionAlgorithm",
                "Force",
                "Type"
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
        $cred = New-Object System.Management.Automation.PSCredential "sqladmin", $passwd

        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($db) {
            $db | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should create a new encryption key using piping" {
            $results = $db | New-DbaDbEncryptionKey -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
        It "should create a new encryption key" {
            $null = Get-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $db.Name | Remove-DbaDbEncryptionKey
            $results = New-DbaDbEncryptionKey -SqlInstance $TestConfig.InstanceSingle -Database $db.Name -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a fresh database for output validation
            $outputDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle

            $outputMasterCert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $outputMasterCert) {
                $delOutputMasterCert = $true
                $outputMasterCert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
            }

            $result = $outputDb | New-DbaDbEncryptionKey -Force -EncryptorName $outputMasterCert.Name

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($outputDb) {
                $outputDb | Remove-DbaDatabase -ErrorAction SilentlyContinue
            }
            if ($delOutputMasterCert) {
                $outputMasterCert | Remove-DbaDbCertificate -ErrorAction SilentlyContinue
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey"
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "CreateDate",
                "EncryptionAlgorithm",
                "EncryptionState",
                "EncryptionType",
                "EncryptorName",
                "ModifyDate",
                "OpenedDate",
                "RegenerateDate",
                "SetDate",
                "Thumbprint"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    Context "Asymmetric key tests" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

            $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database master

            if (-not $masterasym) {
                $delmasterasym = $true
                $masterasym = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database master
            }

            $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $db | New-DbaDbMasterKey -SecurePassword $passwd
            $db | New-DbaDbAsymmetricKey

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($db) {
                $db | Remove-DbaDatabase -ErrorAction SilentlyContinue
            }
            if ($delmasterasym) {
                $masterasym | Remove-DbaDbAsymmetricKey -ErrorAction SilentlyContinue
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # TODO: I think I need some background on this. Was the intention to create the key or not to creeate the key?
        # Currently $warn is:
        # [09:49:20][New-DbaDbEncryptionKey] Failed to create encryption key in random-1299050584 on localhost\sql2016 | Cannot decrypt or encrypt using the specified asymmetric key, either because it has no private key or because the password provided for the private key is incorrect.
        # Will leave it skipped for now.
        Context "Command does not work but warns" {
            # this works on docker, not sure what's up
            It "should warn that it cant create an encryption key" -Skip:$true {
                ($null = $db | New-DbaDbEncryptionKey -Force -Type AsymmetricKey -EncryptorName $masterasym.Name -WarningVariable warn) *> $null
                $warn | Should -Match "n order to encrypt the database encryption key with an as"
            }
        }
    }
}