#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaConnectionString",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-034): connection strings build locally - no connection is
    # attempted - so every scenario runs offline. Exact pins reflect the lab configuration
    # (sql.connection.trustcert=True, sql.connection.packetsize=4096, ConnectTimeout 15).

    Context "Modern provider strings" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "fakepass" -AsPlainText -Force
            $sqlCredential = New-Object System.Management.Automation.PSCredential("sqladmin", $securePassword)
            $winCredential = New-Object System.Management.Automation.PSCredential("ad\sqladmin", $securePassword)
            $azCredential = New-Object System.Management.Automation.PSCredential("me@myad.onmicrosoft.com", $securePassword)
        }

        It "Builds the Windows Authentication string" {
            $result = New-DbaConnectionString -SqlInstance sql2016
            $result | Should -Be "Data Source=sql2016;Integrated Security=True;Multiple Active Result Sets=False;Connect Timeout=15;Trust Server Certificate=True;Packet Size=4096;Application Name=`"dbatools PowerShell module - dbatools.io`""
        }

        It "Embeds a SQL login credential" {
            $result = New-DbaConnectionString -SqlInstance sql2016 -Credential $sqlCredential
            $result | Should -Match "User ID=sqladmin;Password=fakepass"
            $result | Should -Not -Match "Integrated Security"
        }

        It "Rewrites domain\user credentials as user@domain" {
            $result = New-DbaConnectionString -SqlInstance sql2016 -Credential $winCredential
            $result | Should -Match "User ID=sqladmin@ad;"
        }

        It "Configures Azure AD password authentication for Azure instances" {
            $result = New-DbaConnectionString -SqlInstance mydb.database.windows.net -Credential $azCredential -Database db
            $result | Should -Match "Initial Catalog=db"
            $result | Should -Match "Connect Timeout=30"
            $result | Should -Match "Encrypt=True"
            $result | Should -Match "Authentication=ActiveDirectoryPassword"
        }

        It "Uses Active Directory Integrated for Azure without a credential" {
            $result = New-DbaConnectionString -SqlInstance mydb.database.windows.net
            $result | Should -Match "Authentication=ActiveDirectoryIntegrated"
            $result | Should -Not -Match "Integrated Security"
        }
    }

    Context "Legacy provider and guard rails" {
        It "Uses the System.Data keyword spellings under -Legacy" {
            $result = New-DbaConnectionString -SqlInstance sql2016 -Legacy
            $result | Should -Match "MultipleActiveResultSets=False"
            $result | Should -Match "TrustServerCertificate=True"
        }

        It "Warns that LockTimeout is not part of a connection string" {
            $result = New-DbaConnectionString -SqlInstance sql2016 -LockTimeout 5 -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Match "Parameter LockTimeout not supported, because it is not part of a connection string"
            $result | Should -Match "^Data Source=sql2016;"
        }

        It "Emits nothing under -WhatIf" {
            $results = @(New-DbaConnectionString -SqlInstance sql2016 -WhatIf)
            $results.Count | Should -BeExactly 0
        }
    }

    Context "Cross-record isAzure latch under sql.connection.legacy (DEF-008 W1-027)" {
        BeforeAll {
            $legacyConfigOriginal = Get-DbatoolsConfigValue -FullName sql.connection.legacy
            $null = Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            $latchPassword = ConvertTo-SecureString -String "fakepass" -AsPlainText -Force
            $latchCredential = New-Object System.Management.Automation.PSCredential("me@myad.onmicrosoft.com", $latchPassword)
        }

        AfterAll {
            $null = Set-DbatoolsConfig -FullName sql.connection.legacy -Value $legacyConfigOriginal
        }

        It "Latches the Azure auth branch onto later non-Azure records like the source" {
            # The source's $isAzure = $true is FUNCTION scope and never reset, so once an
            # Azure instance latches it, a plain instance later in the SAME pipeline gets
            # the Azure auth string appended too (quirk preserved, not a recommendation).
            $latchedResults = @("mydb.database.windows.net", "sql2016" | New-DbaConnectionString -Credential $latchCredential)
            $latchedResults.Count | Should -BeExactly 2
            $latchedResults[0] | Should -Match "Active Directory Password"
            $latchedResults[1] | Should -Match "Active Directory Password"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>