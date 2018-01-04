function Copy-DbaCredential {
    <#
        .SYNOPSIS
            Copy-DbaCredential migrates SQL Server Credentials from one SQL Server to another while maintaining Credential passwords.

        .DESCRIPTION
            By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Credentials from one server to another while maintaining username and password.

            Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
            License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Credential
             This command requires access to the Windows OS via PowerShell remoting. Use this credential to connect to Windows using alternative credentials.

        .PARAMETER CredentialIdentity
            Auto-populated list of Credentials from Source. If no Credential is specified, all Credentials will be migrated. If spaces exist in the credential name, it must be wrapped with quotes.

        .PARAMETER ExcludeCredentialIdentity
            Auto-populated list of Credentials from Source to be excluded from the migration.

        .PARAMETER Force
            If this switch is enabled, the Credential will be dropped and recreated if it already exists on Destination.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: WSMan, Migration
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires:
                - PowerShell Version 3.0, SQL Server SMO,
                - Administrator access on Windows
                - sysadmin access on SQL Server.
                - DAC access enabled for local (default)
            Limitations: Hasn't been tested thoroughly. Works on Win8.1 and SQL Server 2012 & 2014 so far.

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaCredential

        .EXAMPLE
            Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster

            Copies all SQL Server Credentials on sqlserver2014a to sqlcluster. If Credentials exist on destination, they will be skipped.

        .EXAMPLE
            Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster -CredentialIdentity "PowerShell Proxy Account" -Force

            Copies over one SQL Server Credential (PowerShell Proxy Account) from sqlserver to sqlcluster. If the Credential already exists on the destination, it will be dropped and recreated.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [PSCredential]
        $Credential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$CredentialIdentity,
        [object[]]$ExcludeCredentialIdentity,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        $null = Test-ElevationRequirement -ComputerName $Source.ComputerName

        function Get-SqlCredential {
            <#
                .SYNOPSIS
                    Gets Credential Logins

                    This function is heavily based on Antti Rantasaari's script at http://goo.gl/omEOrW
                    Antti Rantasaari 2014, NetSPI
                    License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

                .OUTPUT
                    System.Data.DataTable
            #>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
            param (
                [DbaInstanceParameter]$SqlInstance,
                [PSCredential]$SqlCredential
            )

            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            $sourceName = $server.Name

            # Query Service Master Key from the database - remove padding from the key
            # key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
            $sql = "SELECT substring(crypt_property,9,len(crypt_property)-8) FROM sys.key_encryptions WHERE key_id=102 and (thumbprint=0x03 or thumbprint=0x0300000001)"
            try {
                $smkBytes = $server.ConnectionContext.ExecuteScalar($sql)
            }
            catch {
                throw "Can't execute SQL on $sourceName"
            }

            $sourceNetBios = Resolve-NetBiosName $server
            $instance = $server.InstanceName
            $serviceInstanceId = $server.ServiceInstanceId

            # Get entropy from the registry - hopefully finds the right SQL server instance
            try {
                [byte[]]$entropy = Invoke-Command2 -ComputerName $sourceNetBios -Credential $Credential -ArgumentList $serviceInstanceId -ScriptBlock {
                    $serviceInstanceId = $args[0]
                    $entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\").Entropy
                    return $entropy
                } -Raw
            }
            catch {
                throw "Can't access registry keys on $sourceName. Quitting. $_"
            }

            # Decrypt the service master key
            try {
                $serviceKey = Invoke-Command2 -ComputerName $sourceNetBios -Credential $Credential -ArgumentList $smkBytes, $Entropy -ScriptBlock {
                    Add-Type -AssemblyName System.Security
                    Add-Type -AssemblyName System.Core
                    $smkBytes = $args[0]; $Entropy = $args[1]
                    $serviceKey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkBytes, $Entropy, 'LocalMachine')
                    return $serviceKey
                } -Raw
            }
            catch {
                throw "Can't unprotect registry data on $($source.Name)). Quitting."
            }

            <#
                Choose the encryption algorithm based on the SMK length:
                    3DES for 2008, AES for 2012
                Choose IV length based on the algorithm
            #>
            if (($serviceKey.Length -ne 16) -and ($serviceKey.Length -ne 32)) {
                throw "Unknown key size. Cannot continue. Quitting."
            }

            if ($serviceKey.Length -eq 16) {
                $decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
                $ivlen = 8
            }
            elseif ($serviceKey.Length -eq 32) {
                $decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
                $ivlen = 16
            }

            <#
                Query link server password information from the Db. Remove header from pwdhash,
                    extract IV (as iv) and ciphertext (as pass).
                Ignore links with blank credentials (integrated auth ?)
            #>
            if ($server.IsClustered -eq $false) {
                $connString = "Server=ADMIN:$sourceNetBios\$instance;Trusted_Connection=True"
            }
            else {
                $dacEnabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue


                if ($dacEnabled -eq $false) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Enabling DAC on clustered instance")) {
                        Write-Message -Level Verbose -Message "DAC must be enabled for clusters, even when accessed from active node. Enabling."
                        $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
                        $server.Configuration.Alter()
                    }
                }

                $connString = "Server=ADMIN:$sourceName;Trusted_Connection=True"
            }

            $sql = "SELECT QUOTENAME(name) AS name,credential_identity,substring(imageval,5,$ivlen) iv, substring(imageval,$($ivlen + 5),len(imageval)-$($ivlen + 4)) pass from sys.Credentials cred inner join sys.sysobjvalues obj on cred.credential_id = obj.objid where valclass=28 and valnum=2"

            # Get entropy from the registry
            try {
                $creds = Invoke-Command2 -ComputerName $sourceNetBios -Credential $Credential -ArgumentList $connString, $sql -ScriptBlock {
                    $connString = $args[0]; $sql = $args[1]
                    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
                    try {
                        $conn.Open()
                        $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn);
                        $data = $cmd.ExecuteReader()
                        $dt = New-Object "System.Data.DataTable"
                        $dt.Load($data)
                        $conn.Close()
                        $conn.Dispose()
                        return $dt
                    }
                    catch {
                        Stop-Function -Message "Can't establish local DAC connection to $sourceName or other error. Quitting." -ErrorRecord $_
                        return
                    }
                } -Raw
            }
            catch {
                Stop-Function -Message "Can't establish local DAC connection to $sourceName or other error. Quitting." -ErrorRecord $_
                return
            }

            if ($server.IsClustered -and $dacEnabled -eq $false) {
                if ($Pscmdlet.ShouldProcess($server.Name, "Disabling DAC on clustered instance")) {
                    Write-Message -Level Verbose -Message "Setting DAC config back to 0"
                    $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
                    $server.Configuration.Alter()
                }
            }

            $decryptedLogins = New-Object "System.Data.DataTable"
            [void]$decryptedLogins.Columns.Add("Credential")
            [void]$decryptedLogins.Columns.Add("Identity")
            [void]$decryptedLogins.Columns.Add("Password")

            # Go through each row in results
            foreach ($cred in $creds) {
                # decrypt the password using the service master key and the extracted IV
                $decryptor.Padding = "None"
                $decrypt = $decryptor.CreateEncryptor($serviceKey, $cred.iv)
                $stream = New-Object System.IO.MemoryStream ( , $cred.pass)
                $crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"

                $crypto.Write($cred.Pass, 0, $cred.Pass.Length)
                [byte[]]$decrypted = $stream.ToArray()

                # convert decrypted password to unicode
                $encode = New-Object System.Text.UnicodeEncoding

                <#
                    Print results - removing the weird padding (8 bytes in the front, some bytes at the end)...
                    Might cause problems but so far seems to work.. may be dependant on SQL server version...
                    If problems arise remove the next three lines..
                #>
                $i = 8
                foreach ($b in $decrypted) {
                    if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) {
                        $i -= 1
                        break
                    }
                    $i += 1
                }
                $decrypted = $decrypted[8 .. $i]

                [void]$decryptedLogins.Rows.Add($($cred.Name), $($cred.Credential_Identity), $($encode.GetString($decrypted)))
            }
            return $decryptedLogins
        }

        function Copy-Credential {
            <#
                .SYNOPSIS
                    Copies Credentials from one server to another using a combination of SMO's .Script() and manual password updates.

                .OUTPUT
                    System.Data.DataTable
            #>
            param (
                [string[]]$credentials,
                [bool]$force
            )

            Write-Message -Level Verbose -Message "Collecting Credential logins and passwords on $($sourceServer.Name)"
            $sourceCredentials = Get-SqlCredential $sourceServer
            $credentialList = $sourceServer.Credentials

            if ($CredentialIdentity) {
                $credentialList = $credentialList | Where-Object { $CredentialIdentity -contains $_.Name }
            }

            if ($ExcludeCredentialIdentity) {
                $credentialList = $credentialList | Where-Object { $CredentialIdentity -notcontains $_.Name }
            }

            Write-Message -Level Verbose -Message "Starting migration"
            foreach ($credential in $credentialList) {
                $destServer.Credentials.Refresh()
                $credentialName = $credential.Name

                $copyCredentialStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Credential"
                    Name              = $credentialName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($destServer.Credentials[$credentialName] -ne $null) {
                    if (!$force) {
                        $copyCredentialStatus.Status = "Skipping"
                        $copyCredentialStatus.Notes = "Already exists"
                        $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "$credentialName exists $($destServer.Name). Skipping."
                        continue
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($destination.Name, "Dropping $identity")) {
                            $destServer.Credentials[$credentialName].Drop()
                            $destServer.Credentials.Refresh()
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate $credentialName"
                try {
                    $currentCred = $sourceCredentials | Where-Object { $_.Credential -eq "[$credentialName]" }
                    $identity = $currentCred.Identity
                    $password = $currentCred.Password
                    if ($Pscmdlet.ShouldProcess($destination.Name, "Copying $identity")) {
                        $sql = "CREATE CREDENTIAL [$credentialName] WITH IDENTITY = N'$identity', SECRET = N'$password'"
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)
                        $destServer.Credentials.Refresh()
                        Write-Message -Level Verbose -Message "$credentialName successfully copied"
                    }

                    $copyCredentialStatus.Status = "Successful"
                    $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                catch {
                    $copyCredentialStatus.Status = "Failed"
                    $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Error creating credential" -Target $credentialName -ErrorRecord $_
                }
            }
        }

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        if ($SourceSqlCredential.Username -ne $null) {
            Write-Message -Level Verbose -Message "You are using SQL credentials and this script requires Windows admin access to the $Source server. Trying anyway."
        }

        if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
            throw "Credentials are only supported in SQL Server 2005 and above. Quitting."
        }

        Invoke-SmoCheck -SqlInstance $sourceServer
        Invoke-SmoCheck -SqlInstance $destServer
    }
    process {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Level Verbose -Message "Getting NetBios name for $source"
        $sourceNetBios = Resolve-NetBiosName $sourceServer

        # This output is wrong. Will fix later.
        Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $source"
        try {
            Invoke-Command2 -ComputerName $sourceNetBios -Credential $credential -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" }
        }
        catch {
            Stop-Function -Message "Can't connect to registry on $source." -Target $sourceNetBios -ErrorRecord $_
            return
        }

        # Magic happens here
        Copy-Credential $credentials -force:$force
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlCredential
    }
}
