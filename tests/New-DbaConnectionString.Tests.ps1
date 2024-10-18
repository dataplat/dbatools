param($ModuleName = 'dbatools')

Describe "New-DbaConnectionString" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaConnectionString
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have AccessToken as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter AccessToken -Type System.String -Mandatory:$false
        }
        It "Should have ApplicationIntent as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ApplicationIntent -Type System.String -Mandatory:$false
        }
        It "Should have BatchSeparator as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Type System.String -Mandatory:$false
        }
        It "Should have ClientName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ClientName -Type System.String -Mandatory:$false
        }
        It "Should have ConnectTimeout as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter ConnectTimeout -Type System.Int32 -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String -Mandatory:$false
        }
        It "Should have EncryptConnection as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptConnection -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have FailoverPartner as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter FailoverPartner -Type System.String -Mandatory:$false
        }
        It "Should have IsActiveDirectoryUniversalAuth as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsActiveDirectoryUniversalAuth -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have LockTimeout as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter LockTimeout -Type System.Int32 -Mandatory:$false
        }
        It "Should have MaxPoolSize as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter MaxPoolSize -Type System.Int32 -Mandatory:$false
        }
        It "Should have MinPoolSize as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter MinPoolSize -Type System.Int32 -Mandatory:$false
        }
        It "Should have MultipleActiveResultSets as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter MultipleActiveResultSets -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have MultiSubnetFailover as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter MultiSubnetFailover -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have NetworkProtocol as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter NetworkProtocol -Type System.String -Mandatory:$false
        }
        It "Should have NonPooledConnection as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NonPooledConnection -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have PacketSize as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter PacketSize -Type System.Int32 -Mandatory:$false
        }
        It "Should have PooledConnectionLifetime as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter PooledConnectionLifetime -Type System.Int32 -Mandatory:$false
        }
        It "Should have SqlExecutionModes as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter SqlExecutionModes -Type System.String -Mandatory:$false
        }
        It "Should have StatementTimeout as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter StatementTimeout -Type System.Int32 -Mandatory:$false
        }
        It "Should have TrustServerCertificate as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter TrustServerCertificate -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have WorkstationId as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter WorkstationId -Type System.String -Mandatory:$false
        }
        It "Should have Legacy as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Legacy -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have AppendConnectionString as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter AppendConnectionString -Type System.String -Mandatory:$false
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
