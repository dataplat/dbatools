#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Credential",
                "Destination",
                "DestinationSqlCredential",
                "Name",
                "ExcludeName",
                "Identity",
                "ExcludeIdentity",
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

        $credLogins = @("thor", "thorsmomma", "thor_crypto")
        $plaintext = "BigOlPassword!"
        $credPassword = ConvertTo-SecureString $plaintext -AsPlainText -Force

        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $server3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        # Add user
        foreach ($login in $credLogins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $TestConfig.InstanceCopy1
        }

        <#
            New tests have been added for validating a credential that uses a crypto provider. (Ref: https://github.com/dataplat/dbatools/issues/7896)

            The new pester tests will only run if a crypto provider is registered and enabled.

            Follow these steps to configure the local machine to run the crypto provider tests.

            1. Run these SQL commands on the InstanceSingle and instance3 servers:

            -- Enable advanced options.
            USE master;
            GO
            sp_configure 'show advanced options', 1;
            GO
            RECONFIGURE;
            GO
            -- Enable EKM provider
            sp_configure 'EKM provider enabled', 1;
            GO
            RECONFIGURE;

            2. Install https://www.microsoft.com/en-us/download/details.aspx?id=45344 on the InstanceSingle and instance3 servers.

            3. Run these SQL commands on the InstanceSingle and instance3 servers:

            CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'
        #>

        # check to see if a crypto provider is present on the instances
        $InstanceSingleCryptoProviders = $server2.Query("SELECT name FROM sys.cryptographic_providers WHERE is_enabled = 1 ORDER BY name")
        $instance3CryptoProviders = $server3.Query("SELECT name FROM sys.cryptographic_providers WHERE is_enabled = 1 ORDER BY name")

        $cryptoProvider = ($InstanceSingleCryptoProviders | Where-Object { $PSItem.name -eq $instance3CryptoProviders.name } | Select-Object -First 1).name

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaCredential -SqlInstance $server2, $server3 -Identity thor, thorsmomma, thor_crypto | Remove-DbaCredential

        foreach ($login in $credLogins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $TestConfig.InstanceCopy1
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Create new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $server2 -Name thorcred -Identity thor -Password $credPassword
            $results.Name | Should -Be "thorcred"
            $results.Identity | Should -Be "thor"

            $results = New-DbaCredential -SqlInstance $server2 -Identity thorsmomma -Password $credPassword
            $results.Name | Should -Be "thorsmomma"
            $results.Identity | Should -Be "thorsmomma"

            if ($cryptoProvider) {
                $splatCryptoNew = @{
                    SqlInstance     = $server2
                    Identity        = "thor_crypto"
                    Password        = $credPassword
                    MappedClassType = "CryptographicProvider"
                    ProviderName    = $cryptoProvider
                }
                $results = New-DbaCredential @splatCryptoNew
                $results.Name | Should -Be "thor_crypto"
                $results.Identity | Should -Be "thor_crypto"
                $results.ProviderName | Should -Be $cryptoProvider
            }
        }
    }

    Context "Copy Credential with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name thorcred
            $results.Status | Should -Be "Successful"
        }

        It "Should retain its same properties" {
            $Credential1 = Get-DbaCredential -SqlInstance $server2 -Name thor
            $Credential2 = Get-DbaCredential -SqlInstance $server3 -Name thor

            # Compare its value
            $Credential1.Name | Should -Be $Credential2.Name
            $Credential1.Identity | Should -Be $Credential2.Identity
        }
    }

    Context "No overwrite" {
        It "does not overwrite without force" {
            $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name thorcred
            $results.Status | Should -Be "Skipping"
        }
    }

    # See https://github.com/dataplat/dbatools/issues/7896 and comments above in BeforeAll
    Context "Crypto provider cred" {
        It "ensure copied credential is using the same crypto provider" {
            if ($cryptoProvider) {
                $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name thor_crypto
                $results.Status | Should -Be "Successful"
                $results = Get-DbaCredential -SqlInstance $server3 -Name thor_crypto
                $results.Name | Should -Be "thor_crypto"
                $results.ProviderName | Should -Be $cryptoProvider
            }
        }

        It "check warning message if crypto provider is not configured/enabled on destination" {
            if ($cryptoProvider) {
                Remove-DbaCredential -SqlInstance $server3 -Credential thor_crypto
                $server3.Query("ALTER CRYPTOGRAPHIC PROVIDER $cryptoProvider DISABLE")
                $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name thor_crypto
                $server3.Query("ALTER CRYPTOGRAPHIC PROVIDER $cryptoProvider ENABLE")
                $results.Status | Should -Be "Failed"
                $results.Notes | Should -Match "The cryptographic provider $cryptoProvider needs to be configured and enabled on"
            }
        }
    }
}