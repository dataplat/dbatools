param($ModuleName = 'dbatools')

Describe "New-DbaConnectionString" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaConnectionString
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "AccessToken",
                "ApplicationIntent",
                "BatchSeparator",
                "ClientName",
                "ConnectTimeout",
                "Database",
                "EncryptConnection",
                "FailoverPartner",
                "IsActiveDirectoryUniversalAuth",
                "LockTimeout",
                "MaxPoolSize",
                "MinPoolSize",
                "MultipleActiveResultSets",
                "MultiSubnetFailover",
                "NetworkProtocol",
                "NonPooledConnection",
                "PacketSize",
                "PooledConnectionLifetime",
                "SqlExecutionModes",
                "StatementTimeout",
                "TrustServerCertificate",
                "WorkstationId",
                "Legacy",
                "AppendConnectionString"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param -Mandatory:$false
            }
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
