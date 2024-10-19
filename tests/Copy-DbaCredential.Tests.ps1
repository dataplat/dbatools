param($ModuleName = 'dbatools')

Describe "Copy-DbaCredential" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"

        $logins = "dbatoolsci_thor", "dbatoolsci_thorsmomma", "dbatoolsci_thor_crypto"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        $server2 = Connect-DbaInstance -SqlInstance $global:instance2
        $server3 = Connect-DbaInstance -SqlInstance $global:instance3

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $global:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $global:instance3
        }

        # check to see if a crypto provider is present on the instances
        $instance2CryptoProviders = $server2.Query("SELECT name FROM sys.cryptographic_providers WHERE is_enabled = 1 ORDER BY name")
        $instance3CryptoProviders = $server3.Query("SELECT name FROM sys.cryptographic_providers WHERE is_enabled = 1 ORDER BY name")

        $cryptoProvider = ($instance2CryptoProviders | Where-Object { $_.name -eq $instance3CryptoProviders.name } | Select-Object -First 1).name
    }

    AfterAll {
        (Get-DbaCredential -SqlInstance $server2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma, dbatoolsci_thor_crypto -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        (Get-DbaCredential -SqlInstance $server3 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma, dbatoolsci_thor_crypto -ErrorAction Stop -WarningAction SilentlyContinue).Drop()

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $global:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $global:instance3
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaCredential
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have ExcludeName parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeName
        }
        It "Should have Identity parameter" {
            $CommandUnderTest | Should -HaveParameter Identity
        }
        It "Should have ExcludeIdentity parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeIdentity
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Create new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $server2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
            $results.Name | Should -Be "dbatoolsci_thorcred"
            $results.Identity | Should -Be "dbatoolsci_thor"

            $results = New-DbaCredential -SqlInstance $server2 -Identity dbatoolsci_thorsmomma -Password $password
            $results.Name | Should -Be "dbatoolsci_thorsmomma"
            $results.Identity | Should -Be "dbatoolsci_thorsmomma"

            if ($cryptoProvider) {
                $results = New-DbaCredential -SqlInstance $server2 -Identity dbatoolsci_thor_crypto -Password $password -MappedClassType CryptographicProvider -ProviderName $cryptoProvider
                $results.Name | Should -Be "dbatoolsci_thor_crypto"
                $results.Identity | Should -Be "dbatoolsci_thor_crypto"
                $results.ProviderName | Should -Be $cryptoProvider
            }
        }
    }

    Context "Copy Credential with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name dbatoolsci_thorcred
            $results.Status | Should -Be "Successful"
        }

        It "Should retain its same properties" {
            $Credential1 = Get-DbaCredential -SqlInstance $server2 -Name dbatoolsci_thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Credential2 = Get-DbaCredential -SqlInstance $server3 -Name dbatoolsci_thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Compare its value
            $Credential1.Name | Should -Be $Credential2.Name
            $Credential1.Identity | Should -Be $Credential2.Identity
        }
    }

    Context "No overwrite" {
        It "does not overwrite without force" {
            $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name dbatoolsci_thorcred
            $results.Status | Should -Be "Skipping"
        }
    }

    Context "Crypto provider cred" {
        BeforeDiscovery {
            $global:skipCryptoTests = -not $cryptoProvider
        }

        It "ensure copied credential is using the same crypto provider" -Skip:$skipCryptoTests {
            $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name dbatoolsci_thor_crypto
            $results.Status | Should -Be Successful
            $results = Get-DbaCredential -SqlInstance $server3 -Name dbatoolsci_thor_crypto
            $results.Name | Should -Be dbatoolsci_thor_crypto
            $results.ProviderName | Should -Be $cryptoProvider
        }

        It "check warning message if crypto provider is not configured/enabled on destination" -Skip:$skipCryptoTests {
            Remove-DbaCredential -SqlInstance $server3 -Credential dbatoolsci_thor_crypto -Confirm:$false
            $server3.Query("ALTER CRYPTOGRAPHIC PROVIDER $cryptoProvider DISABLE")
            $results = Copy-DbaCredential -Source $server2 -Destination $server3 -Name dbatoolsci_thor_crypto
            $server3.Query("ALTER CRYPTOGRAPHIC PROVIDER $cryptoProvider ENABLE")
            $results.Status | Should -Be Failed
            $results.Notes | Should -Match "The cryptographic provider $cryptoProvider needs to be configured and enabled on"
        }
    }
}
