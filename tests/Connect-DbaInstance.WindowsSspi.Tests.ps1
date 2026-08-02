#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Connect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    $script:unsupportedPlatform = $PSVersionTable.PSEdition -ne "Core" -or -not $IsWindows
}

Describe "$CommandName Windows SSPI" -Tag IntegrationTests {
    Context "explicit Windows credentials use the SqlClient SSPI provider" -Skip:$script:unsupportedPlatform {
        BeforeAll {
            if (-not ("Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider" -as [type])) {
                throw "The PowerShell 7 SSPI integration test requires a dbatools.library build with NetworkCredentialSspiContextProvider."
            }

            $script:sspiUserName = "dbasspi$([guid]::NewGuid().ToString("N").Substring(0, 8))"
            $splatPassword = @{
                String      = "Dba!$(New-Guid)9x"
                AsPlainText = $true
                Force       = $true
            }
            $script:sspiPassword = ConvertTo-SecureString @splatPassword
            $script:sspiPrincipal = "$env:COMPUTERNAME\$script:sspiUserName"
            $script:sspiCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $script:sspiPrincipal, $script:sspiPassword
            $script:sspiUserCreated = $false

            $splatLocalUser = @{
                Name                 = $script:sspiUserName
                Password             = $script:sspiPassword
                AccountNeverExpires  = $true
                PasswordNeverExpires = $true
                ErrorAction          = "Stop"
            }
            $null = New-LocalUser @splatLocalUser
            $script:sspiUserCreated = $true

            $splatAdmin = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $TestConfig.SqlCred
                TrustServerCertificate = $true
                ErrorAction            = "Stop"
            }
            $adminServer = Connect-DbaInstance @splatAdmin
            try {
                $escapedPrincipal = $script:sspiPrincipal.Replace("]", "]]")
                $adminServer.Query("CREATE LOGIN [$escapedPrincipal] FROM WINDOWS")
            } finally {
                $adminServer.ConnectionContext.Disconnect()
            }
        }

        AfterAll {
            try {
                if ($script:sspiUserCreated) {
                    $splatAdmin = @{
                        SqlInstance            = $TestConfig.InstanceSingle
                        SqlCredential          = $TestConfig.SqlCred
                        TrustServerCertificate = $true
                        ErrorAction            = "Stop"
                    }
                    $adminServer = Connect-DbaInstance @splatAdmin
                    try {
                        $escapedPrincipal = $script:sspiPrincipal.Replace("]", "]]")
                        $escapedLiteral = $script:sspiPrincipal.Replace("'", "''")
                        $adminServer.Query("IF SUSER_ID(N'$escapedLiteral') IS NOT NULL DROP LOGIN [$escapedPrincipal]")
                    } finally {
                        $adminServer.ConnectionContext.Disconnect()
                    }
                }
            } finally {
                if ($script:sspiUserCreated) {
                    Remove-LocalUser -Name $script:sspiUserName -ErrorAction SilentlyContinue
                }
                $script:sspiCredential = $null
                $script:sspiPassword = $null
            }
        }

        It "reopens the same provider-backed connection" {
            $splatConnect = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $script:sspiCredential
                NonPooledConnection    = $true
                TrustServerCertificate = $true
                ErrorAction            = "Stop"
            }
            $server = Connect-DbaInstance @splatConnect
            $connection = $server.ConnectionContext.SqlConnectionObject
            $provider = $connection.SspiContextProvider

            try {
                $provider | Should -BeOfType Dataplat.Dbatools.Connection.NetworkCredentialSspiContextProvider
                $server.ConnectionContext.Disconnect()

                foreach ($attempt in 1..2) {
                    $connection.Open()
                    $command = $connection.CreateCommand()
                    try {
                        $command.CommandText = "SELECT ORIGINAL_LOGIN()"
                        $command.ExecuteScalar() | Should -Be $script:sspiPrincipal
                    } finally {
                        $command.Dispose()
                        $connection.Close()
                    }
                }
            } finally {
                if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
                    $connection.Close()
                }
                $connection.Dispose()
                if ($provider) {
                    $provider.Dispose()
                }
            }
        }

        It "still caches a Server input that follows an SSPI connection in the same call" {
            # The SSPI provider path suppresses connection caching for its own instance.
            # That suppression is tracked in a single loop variable, so a later element of
            # the same call must not inherit it. Only the string input path can set the
            # flag, which is why this needs a real connected Server object as the second
            # element rather than another string.
            $splatSeed = @{
                SqlInstance            = $TestConfig.InstanceSingle
                SqlCredential          = $TestConfig.SqlCred
                TrustServerCertificate = $true
                ErrorAction            = "Stop"
            }
            $seedServer = Connect-DbaInstance @splatSeed
            $servers = $null

            try {
                $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
                Clear-DbaConnectionPool

                $splatMixed = @{
                    SqlInstance            = @($TestConfig.InstanceSingle, $seedServer)
                    SqlCredential          = $script:sspiCredential
                    TrustServerCertificate = $true
                    ErrorAction            = "Stop"
                }
                $servers = @(Connect-DbaInstance @splatMixed)

                $servers.Count | Should -Be 2

                # The SSPI element is never cached, so after the pre-call clear any entry
                # here has to come from the Server element. The leak suppressed it too,
                # leaving the cache empty.
                $cached = @(Get-DbaConnectedInstance | Where-Object ConnectionType -match "Smo\.Server$")
                $cached.Count | Should -Be 1
            } finally {
                # The SSPI-backed connection is deliberately kept out of the connection
                # hash, so Disconnect-DbaInstance cannot reach it. Release it by hand or
                # the connection and its provider outlive the test.
                if ($servers -and $servers[0]) {
                    $sspiConnection = $servers[0].ConnectionContext.SqlConnectionObject
                    $servers[0].ConnectionContext.Disconnect()
                    if ($sspiConnection) {
                        $sspiProvider = $sspiConnection.SspiContextProvider
                        if ($sspiConnection.State -ne [System.Data.ConnectionState]::Closed) {
                            $sspiConnection.Close()
                        }
                        $sspiConnection.Dispose()
                        if ($sspiProvider) {
                            $sspiProvider.Dispose()
                        }
                    }
                }
                $seedServer.ConnectionContext.Disconnect()
                $null = Get-DbaConnectedInstance | Disconnect-DbaInstance
                Clear-DbaConnectionPool
            }
        }
    }
}
