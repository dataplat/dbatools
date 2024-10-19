param($ModuleName = 'dbatools')

Describe "New-DbaConnectionString" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaConnectionString
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Mandatory:$false
        }
        It "Should have AccessToken as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter AccessToken -Mandatory:$false
        }
        It "Should have ApplicationIntent as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ApplicationIntent -Mandatory:$false
        }
        It "Should have BatchSeparator as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Mandatory:$false
        }
        It "Should have ClientName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ClientName -Mandatory:$false
        }
        It "Should have ConnectTimeout as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectTimeout -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Mandatory:$false
        }
        It "Should have EncryptConnection as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptConnection -Mandatory:$false
        }
        It "Should have FailoverPartner as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverPartner -Mandatory:$false
        }
        It "Should have IsActiveDirectoryUniversalAuth as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsActiveDirectoryUniversalAuth -Mandatory:$false
        }
        It "Should have LockTimeout as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LockTimeout -Mandatory:$false
        }
        It "Should have MaxPoolSize as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter MaxPoolSize -Mandatory:$false
        }
        It "Should have MinPoolSize as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter MinPoolSize -Mandatory:$false
        }
        It "Should have MultipleActiveResultSets as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter MultipleActiveResultSets -Mandatory:$false
        }
        It "Should have MultiSubnetFailover as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter MultiSubnetFailover -Mandatory:$false
        }
        It "Should have NetworkProtocol as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter NetworkProtocol -Mandatory:$false
        }
        It "Should have NonPooledConnection as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NonPooledConnection -Mandatory:$false
        }
        It "Should have PacketSize as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PacketSize -Mandatory:$false
        }
        It "Should have PooledConnectionLifetime as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PooledConnectionLifetime -Mandatory:$false
        }
        It "Should have SqlExecutionModes as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlExecutionModes -Mandatory:$false
        }
        It "Should have StatementTimeout as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter StatementTimeout -Mandatory:$false
        }
        It "Should have TrustServerCertificate as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter TrustServerCertificate -Mandatory:$false
        }
        It "Should have WorkstationId as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter WorkstationId -Mandatory:$false
        }
        It "Should have Legacy as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Legacy -Mandatory:$false
        }
        It "Should have AppendConnectionString as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter AppendConnectionString -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Creates a valid connection string" {
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -Database 'master'
            $connectionString | Should -Match "Data Source=$([regex]::Escape($global:instance1))"
            $connectionString | Should -Match "Initial Catalog=master"
        }

        It "Appends custom string when using AppendConnectionString" {
            $customString = "Application Name=MyApp"
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -AppendConnectionString $customString
            $connectionString | Should -Match $customString
        }

        It "Uses provided credentials" {
            $securePassword = ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ('testuser', $securePassword)
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -Credential $cred
            $connectionString | Should -Match "User ID=testuser"
            $connectionString | Should -Match "Password=P@ssw0rd"
        }

        It "Sets ApplicationIntent when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -ApplicationIntent ReadOnly
            $connectionString | Should -Match "ApplicationIntent=ReadOnly"
        }

        It "Sets ConnectTimeout when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -ConnectTimeout 30
            $connectionString | Should -Match "Connect Timeout=30"
        }

        It "Sets EncryptConnection when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -EncryptConnection
            $connectionString | Should -Match "Encrypt=True"
        }

        It "Sets MultiSubnetFailover when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $global:instance1 -MultiSubnetFailover
            $connectionString | Should -Match "MultiSubnetFailover=True"
        }
    }
}
