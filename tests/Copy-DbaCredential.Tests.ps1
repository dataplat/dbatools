param($ModuleName = 'dbatools')

Describe "Copy-DbaCredential" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"
    }

    BeforeAll {
        $logins = "dbatoolsci_thor", "dbatoolsci_thorsmomma", "dbatoolsci_thor_crypto"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        $global:server2 = Connect-DbaInstance -SqlInstance $global:instance2
        $global:server3 = Connect-DbaInstance -SqlInstance $global:instance3

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $global:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $global:instance3
        }

        # check to see if a crypto provider is present on the instances
        $instance2CryptoProviders = $global:server2.Query("SELECT name FROM sys.cryptographic_providers WHERE is_enabled = 1 ORDER BY name")
        $instance3CryptoProviders = $global:server3.Query("SELECT name FROM sys.cryptographic_providers WHERE is_enabled = 1 ORDER BY name")

        $global:cryptoProvider = ($instance2CryptoProviders | Where-Object { $_.name -eq $instance3CryptoProviders.name } | Select-Object -First 1).name
    }

    AfterAll {
        (Get-DbaCredential -SqlInstance $global:server2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma, dbatoolsci_thor_crypto -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        (Get-DbaCredential -SqlInstance $global:server3 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma, dbatoolsci_thor_crypto -ErrorAction Stop -WarningAction SilentlyContinue).Drop()

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $global:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $global:instance3
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaCredential
        }
        $parms = @(
            'Source',
            'SourceSqlCredential',
            'Credential',
            'Destination',
            'DestinationSqlCredential',
            'Name',
            'ExcludeName',
            'Identity',
            'ExcludeIdentity',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Create new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $global:server2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
            $results.Name | Should -Be "dbatoolsci_thorcred"
            $results.Identity | Should -Be "dbatoolsci_thor"

            $results = New-DbaCredential -SqlInstance $global:server2 -Identity dbatoolsci_thorsmomma -Password $password
            $results.Name | Should -Be "dbatoolsci_thorsmomma"
            $results.Identity | Should -Be "dbatoolsci_thorsmomma"

            if ($global:cryptoProvider) {
                $results = New-DbaCredential -SqlInstance $global:server2 -Identity dbatoolsci_thor_crypto -Password $password -MappedClassType CryptographicProvider -ProviderName $global:cryptoProvider
                $results.Name | Should -Be "dbatoolsci_thor_crypto"
                $results.Identity | Should -Be "dbatoolsci_thor_crypto"
                $results.ProviderName | Should -Be $global:cryptoProvider
            }
        }
    }

    Context "Copy Credential with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaCredential -Source $global:server2 -Destination $global:server3 -Name dbatoolsci_thorcred
            $results.Status | Should -Be "Successful"
        }

        It "Should retain its same properties" {
            $Credential1 = Get-DbaCredential -SqlInstance $global:server2 -Name dbatoolsci_thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Credential2 = Get-DbaCredential -SqlInstance $global:server3 -Name dbatoolsci_thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Compare its value
            $Credential1.Name | Should -Be $Credential2.Name
            $Credential1.Identity | Should -Be $Credential2.Identity
        }
    }

    Context "No overwrite" {
        It "does not overwrite without force" {
            $results = Copy-DbaCredential -Source $global:server2 -Destination $global:server3 -Name dbatoolsci_thorcred
            $results.Status | Should -Be "Skipping"
        }
    }

    Context "Crypto provider cred" {
        It "ensure copied credential is using the same crypto provider" -Skip:(-not $global:cryptoProvider) {
            $results = Copy-DbaCredential -Source $global:server2 -Destination $global:server3 -Name dbatoolsci_thor_crypto
            $results.Status | Should -Be Successful
            $results = Get-DbaCredential -SqlInstance $global:server3 -Name dbatoolsci_thor_crypto
            $results.Name | Should -Be dbatoolsci_thor_crypto
            $results.ProviderName | Should -Be $global:cryptoProvider
        }

        It "check warning message if crypto provider is not configured/enabled on destination" -Skip:(-not $global:cryptoProvider) {
            Remove-DbaCredential -SqlInstance $global:server3 -Credential dbatoolsci_thor_crypto -Confirm:$false
            $global:server3.Query("ALTER CRYPTOGRAPHIC PROVIDER $global:cryptoProvider DISABLE")
            $results = Copy-DbaCredential -Source $global:server2 -Destination $global:server3 -Name dbatoolsci_thor_crypto
            $global:server3.Query("ALTER CRYPTOGRAPHIC PROVIDER $global:cryptoProvider ENABLE")
            $results.Status | Should -Be Failed
            $results.Notes | Should -Match "The cryptographic provider $global:cryptoProvider needs to be configured and enabled on"
        }
    }
}
