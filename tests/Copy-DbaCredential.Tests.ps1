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
                "ExcludePassword",
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

    Context "When the pipeline ends at the first credential" {
        It "Closes the dedicated admin connection" {
            # The name of the source makes the command open a dedicated admin connection of its own. It was closed in the
            # end block only, which Select-Object -First 1 skips, and SQL Server allows only one per instance.
            $firstCredential = Copy-DbaCredential -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Name thorcred | Select-Object -First 1
            $firstCredential.Name | Should -Be "thorcred"

            $dacSessionQuery = "SELECT COUNT(*) AS DacSessions FROM sys.dm_exec_sessions AS s INNER JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1"
            # The session can take a moment to end on the server after the client closed the connection.
            $dacWatch = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                $dacSessions = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dacSessionQuery).DacSessions
                if ($dacSessions -gt 0) {
                    Start-Sleep -Milliseconds 200
                }
            } while ($dacSessions -gt 0 -and $dacWatch.Elapsed.TotalSeconds -lt 5)
            $dacSessions | Should -Be 0
        }
    }

    Context "When the command is stopped while it decrypts the credentials" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dacSessionIdQuery = "SELECT s.session_id FROM sys.dm_exec_sessions AS s INNER JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1"
            $dacSessionsBefore = @((Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dacSessionIdQuery).session_id)

            # A credential created in an open transaction blocks the query of the decryption, which reads every credential
            # through the dedicated admin connection. That holds the command after it opened the connection and before
            # its first output, the time it used to spend in begin, where nothing closed the connection after a stop.
            $blockerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -NonPooledConnection
            $blockerServer.ConnectionContext.BeginTransaction()
            $null = $blockerServer.ConnectionContext.ExecuteNonQuery("CREATE CREDENTIAL [dbatoolsci_stopblocker] WITH IDENTITY = N'dbatoolsci_stopblocker', SECRET = N'dbatools.IO'")
            $blockerSpid = $blockerServer.ConnectionContext.ExecuteScalar("SELECT @@SPID")
            $blockedDacQuery = "SELECT COUNT(*) AS Blocked FROM sys.dm_exec_requests AS r INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id INNER JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1 AND r.blocking_session_id = $blockerSpid"

            # The command runs in a runspace of its own, so the test can stop it as Ctrl+C does. The runspace imports the
            # manifest: an import of the psm1 without a command line skips the type data.
            $splatStopCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Name        = "thorcred"
            }
            if ($TestConfig.SqlCred) {
                $splatStopCopy.SourceSqlCredential = $TestConfig.SqlCred
                $splatStopCopy.DestinationSqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand($CommandName).AddParameters($splatStopCopy)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                $decryptBlocked = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $blockedDacQuery).Blocked -gt 0
                if (-not $decryptBlocked) {
                    Start-Sleep -Milliseconds 100
                }
            } while (-not $decryptBlocked -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 60)

            # A stop does not interrupt a running query, so the transaction ends after the stop was requested and the
            # command stops at its next statement.
            $stopRequest = $stopShell.BeginStop($null, $null)
            $blockerServer.ConnectionContext.RollBackTransaction()
            $stopShell.EndStop($stopRequest)
            $stopState = $stopShell.InvocationStateInfo.State
            $stopShell.Dispose()
            $stopRunspace.Dispose()

            # The session can take a moment to end on the server after the client closed the connection.
            $dacWatch = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                $dacSessionsAfter = @((Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dacSessionIdQuery).session_id | Where-Object { $PSItem -notin $dacSessionsBefore })
                if ($dacSessionsAfter) {
                    Start-Sleep -Milliseconds 200
                }
            } while ($dacSessionsAfter -and $dacWatch.Elapsed.TotalSeconds -lt 5)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $blockerServer | Disconnect-DbaInstance
            # A dedicated admin connection left open by the stopped command would keep every later test from opening one.
            foreach ($dacSessionId in $dacSessionsAfter) {
                $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "KILL $dacSessionId"
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Was stopped while it decrypted the credentials" {
            $decryptBlocked | Should -BeTrue
            $stopState | Should -Be "Stopped"
        }

        It "Closes the dedicated admin connection" {
            $dacSessionsAfter | Should -BeNullOrEmpty
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