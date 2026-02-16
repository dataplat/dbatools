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
            $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyName -Database $databaseName -OutVariable "global:dbatoolsciOutput"
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AsymmetricKey]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.AsymmetricKey"
        }
    }
}