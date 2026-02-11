#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbAsymmetricKey",
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
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets a certificate" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Set variables. They are available in all the It blocks.
            $keyName = "test4"
            $keyName2 = "test5"
            $algorithm = "Rsa4096"
            $dbUser = "keyowner"
            $databaseName = "GetAsKey"

            # Create the objects.
            $newDatabase = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $databaseName
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force

            $splatMasterKey = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Database       = $databaseName
                SecurePassword = $tPassword
            }
            $null = New-DbaDbMasterKey @splatMasterKey

            $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $databaseName -UserName $dbUser

            $splatFirstKey = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $databaseName
                Name            = $keyName
                Owner           = "keyowner"
                Algorithm       = $algorithm
                WarningVariable = "warnvar"
            }
            $null = New-DbaDbAsymmetricKey @splatFirstKey

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created objects.
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $databaseName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should Create new key in GetAsKey called test4" {
            $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyName -Database $databaseName
            $results.Database | Should -Be $databaseName
            $results.DatabaseId | Should -Be $newDatabase.ID
            $results.Name | Should -Be $keyName
            $results.Owner | Should -Be $dbUser
            $results | Should -HaveCount 1
        }

        It "Should work with a piped database" {
            $pipeResults = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $databaseName | Get-DbaDbAsymmetricKey
            $pipeResults.Database | Should -Be $databaseName
            $pipeResults.Name | Should -Be $keyName
            $pipeResults.Owner | Should -Be $dbUser
            $pipeResults | Should -HaveCount 1
        }

        It "Should return 2 keys" {
            # Create second key for this test
            $splatSecondKey = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $databaseName
                Name            = $keyName2
                Owner           = "keyowner"
                Algorithm       = $algorithm
                WarningVariable = "warnvar"
            }
            $null = New-DbaDbAsymmetricKey @splatSecondKey

            $multiResults = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $databaseName | Get-DbaDbAsymmetricKey
            $multiResults | Should -HaveCount 2
            $multiResults.Name | Should -Contain $keyName
            $multiResults.Name | Should -Contain $keyName2
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputDbName = "dbatoolsci_outvalaskey_$(Get-Random)"
            $outputKeyName = "dbatoolsci_outputkey"
            $tOutputPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDbName

            $splatOutputMasterKey = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Database       = $outputDbName
                SecurePassword = $tOutputPassword
                Confirm        = $false
            }
            $null = New-DbaDbMasterKey @splatOutputMasterKey

            $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -UserName "dbatoolsci_outkeyowner"

            $splatOutputKey = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $outputDbName
                Name        = $outputKeyName
                Algorithm   = "Rsa4096"
                Confirm     = $false
            }
            $null = New-DbaDbAsymmetricKey @splatOutputKey

            $result = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Name $outputKeyName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Confirm:$false -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AsymmetricKey"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Name",
                "Owner",
                "KeyEncryptionAlgorithm",
                "KeyLength",
                "PrivateKeyEncryptionType",
                "Thumbprint"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}