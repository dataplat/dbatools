#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Connect-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    $unsupportedPlatform = $PSVersionTable.PSEdition -ne "Core" -or -not $IsWindows
}

Describe "$CommandName Windows SSPI" -Tag IntegrationTests {
    Context "explicit Windows credentials use the SqlClient SSPI provider" -Skip:$unsupportedPlatform {
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
    }
}
