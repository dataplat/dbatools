param($ModuleName = 'dbatools')

Describe "New-DbaConnectionString" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaConnectionString
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have AccessToken as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter AccessToken -Type String -Not -Mandatory
        }
        It "Should have ApplicationIntent as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ApplicationIntent -Type String -Not -Mandatory
        }
        It "Should have BatchSeparator as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Type String -Not -Mandatory
        }
        It "Should have ClientName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ClientName -Type String -Not -Mandatory
        }
        It "Should have ConnectTimeout as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter ConnectTimeout -Type Int32 -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Database -Type String -Not -Mandatory
        }
        It "Should have EncryptConnection as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptConnection -Type Switch -Not -Mandatory
        }
        It "Should have FailoverPartner as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter FailoverPartner -Type String -Not -Mandatory
        }
        It "Should have IsActiveDirectoryUniversalAuth as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsActiveDirectoryUniversalAuth -Type Switch -Not -Mandatory
        }
        It "Should have LockTimeout as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter LockTimeout -Type Int32 -Not -Mandatory
        }
        It "Should have MaxPoolSize as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MaxPoolSize -Type Int32 -Not -Mandatory
        }
        It "Should have MinPoolSize as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MinPoolSize -Type Int32 -Not -Mandatory
        }
        It "Should have MultipleActiveResultSets as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter MultipleActiveResultSets -Type Switch -Not -Mandatory
        }
        It "Should have MultiSubnetFailover as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter MultiSubnetFailover -Type Switch -Not -Mandatory
        }
        It "Should have NetworkProtocol as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter NetworkProtocol -Type String -Not -Mandatory
        }
        It "Should have NonPooledConnection as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NonPooledConnection -Type Switch -Not -Mandatory
        }
        It "Should have PacketSize as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter PacketSize -Type Int32 -Not -Mandatory
        }
        It "Should have PooledConnectionLifetime as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter PooledConnectionLifetime -Type Int32 -Not -Mandatory
        }
        It "Should have SqlExecutionModes as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter SqlExecutionModes -Type String -Not -Mandatory
        }
        It "Should have StatementTimeout as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter StatementTimeout -Type Int32 -Not -Mandatory
        }
        It "Should have TrustServerCertificate as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter TrustServerCertificate -Type Switch -Not -Mandatory
        }
        It "Should have WorkstationId as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter WorkstationId -Type String -Not -Mandatory
        }
        It "Should have Legacy as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Legacy -Type Switch -Not -Mandatory
        }
        It "Should have AppendConnectionString as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter AppendConnectionString -Type String -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Creates a valid connection string" {
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -Database 'master'
            $connectionString | Should -Match "Data Source=$([regex]::Escape($script:instance1))"
            $connectionString | Should -Match "Initial Catalog=master"
        }

        It "Appends custom string when using AppendConnectionString" {
            $customString = "Application Name=MyApp"
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -AppendConnectionString $customString
            $connectionString | Should -Match $customString
        }

        It "Uses provided credentials" {
            $securePassword = ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ('testuser', $securePassword)
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -Credential $cred
            $connectionString | Should -Match "User ID=testuser"
            $connectionString | Should -Match "Password=P@ssw0rd"
        }

        It "Sets ApplicationIntent when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -ApplicationIntent ReadOnly
            $connectionString | Should -Match "ApplicationIntent=ReadOnly"
        }

        It "Sets ConnectTimeout when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -ConnectTimeout 30
            $connectionString | Should -Match "Connect Timeout=30"
        }

        It "Sets EncryptConnection when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -EncryptConnection
            $connectionString | Should -Match "Encrypt=True"
        }

        It "Sets MultiSubnetFailover when provided" {
            $connectionString = New-DbaConnectionString -SqlInstance $script:instance1 -MultiSubnetFailover
            $connectionString | Should -Match "MultiSubnetFailover=True"
        }
    }
}
