function Copy-DbaLinkedServer {
    <#
        .SYNOPSIS
            Copy-DbaLinkedServer migrates Linked Servers from one SQL Server to another. Linked Server logins and passwords are migrated as well.

        .DESCRIPTION
            By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Linked Servers from one server to another, while maintaining username and password.

            Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/
            License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

        .PARAMETER Source
            Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER LinkedServer
            The linked server(s) to process - this list is auto-populated from the server. If unspecified, all linked servers will be processed.

        .PARAMETER ExcludeLinkedServer
            The linked server(s) to exclude - this list is auto-populated from the server

        .PARAMETER UpgradeSqlClient
            Upgrade any SqlClient Linked Server to the current Version

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER Force
            By default, if a Linked Server exists on the source and destination, the Linked Server is not copied over. Specifying -force will drop and recreate the Linked Server on the Destination server.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: WSMan, Migration, LinkedServer
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: sysadmin access on SQL Servers, Remote Registry & Remote Administration enabled and accessible on source server.

            Limitations: Hasn't been tested thoroughly. Works on Win8.1 and SQL Server 2012 & 2014 so far.
            This just copies the SQL portion. It does not copy files (ie. a local SQLite database, or Microsoft Access DB), nor does it configure ODBC entries.

        .LINK
            https://dbatools.io/Copy-DbaLinkedServer

        .EXAMPLE
            Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster

            Description
            Copies all SQL Server Linked Servers on sqlserver2014a to sqlcluster. If Linked Server exists on destination, it will be skipped.

        .EXAMPLE
            Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster -LinkedServer SQL2K5,SQL2k -Force

            Description
            Copies over two SQL Server Linked Servers (SQL2K and SQL2K2) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [switch]$UpgradeSqlClient,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )
    begin {
        $null = Test-ElevationRequirement -ComputerName $Source.ComputerName
        function Get-LinkedServerLogins {
            <#
            .SYNOPSIS
                Internal function.

                This function is heavily based on Antti Rantasaari's script at http://goo.gl/wpqSib
                Antti Rantasaari 2014, NetSPI
                License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause
            #>
            param (
                $SqlInstance
            )

            $server = $SqlInstance
            $sourceName = $server.Name

            # Query Service Master Key from the database - remove padding from the key
            # key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
            $sql = "SELECT substring(crypt_property,9,len(crypt_property)-8) as smk FROM sys.key_encryptions WHERE key_id=102 and (thumbprint=0x03 or thumbprint=0x0300000001)"
            try {
                $smkbytes = $server.Query($sql).smk
            }
            catch {
                Stop-Function -Message "Can't run query." -Target $server -InnerErrorRecord $_
                return
            }

            $sourceNetBios = Resolve-NetBiosName $server
            $instance = $server.InstanceName
            $serviceInstanceId = $server.ServiceInstanceId

            # Get entropy from the registry - hopefully finds the right SQL server instance
            try {
                [byte[]]$entropy = Invoke-Command2 -Raw -Credential $Credential -ComputerName $sourceNetBios -argumentlist $serviceInstanceId {
                    $serviceInstanceId = $args[0]
                    $entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\").Entropy
                    return $entropy
                }
            }
            catch {
                Stop-Function -Message "Can't access registry keys on $sourceName. Quitting." -Target $server ErrorRecord $_
                return
            }

            # Decrypt the service master key
            try {
                $serviceKey = Invoke-Command2 -Raw -Credential $Credential -ComputerName $sourceNetBios -ArgumentList $smkbytes, $Entropy {
                    Add-Type -assembly System.Security
                    Add-Type -assembly System.Core
                    $smkbytes = $args[0]; $Entropy = $args[1]
                    $serviceKey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkbytes, $Entropy, 'LocalMachine')
                    return $serviceKey
                }
            }
            catch {
                Stop-Function -Message "Can't unprotect registry data on $($source.Name)). Quitting." -Target $server -InnerErrorRecord $_
                return
            }

            # Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012
            # Choose IV length based on the algorithm
            if (($serviceKey.Length -ne 16) -and ($serviceKey.Length -ne 32)) {
                Write-Message -Level Verbose -Message "ServiceKey found: $serviceKey.Length"
                Stop-Function -Message "Unknown key size. Cannot continue." -Target $source
                return

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
                Query link server password information from the Db.
                Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
                Ignore links with blank credentials (integrated auth ?)
            #>
            if ($server.IsClustered -eq $false) {
                $connString = "Server=ADMIN:$sourceNetBios\$instance;Trusted_Connection=True"
            }
            else {
                $dacEnabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue

                if ($dacEnabled -eq $false) {
                    If ($Pscmdlet.ShouldProcess($server.Name, "Enabling DAC on clustered instance.")) {
                        Write-Message -Level Verbose -Message "DAC must be enabled for clusters, even when accessed from active node. Enabling."
                        $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
                        $server.Configuration.Alter()
                    }
                }

                $connString = "Server=ADMIN:$sourceName;Trusted_Connection=True"
            }

            <# NOTE: This query is accessing syslnklgns table. Can only be done via the DAC connection #>
            $sql = "
                SELECT sysservers.srvname,
                    syslnklgns.Name,
                    substring(syslnklgns.pwdhash,5,$ivlen) iv,
                    substring(syslnklgns.pwdhash,$($ivlen + 5),
                    len(syslnklgns.pwdhash)-$($ivlen + 4)) pass
                FROM master.sys.syslnklgns
                    inner join master.sys.sysservers
                    on syslnklgns.srvid=sysservers.srvid
                WHERE len(pwdhash) > 0"

            # Get entropy from the registry
            try {
                $logins = Invoke-Command2 -Raw -Credential $Credential -ComputerName $sourceNetBios -ArgumentList $connString, $sql {
                    $connString = $args[0]; $sql = $args[1]
                    $conn = New-Object System.Data.SqlClient.SQLConnection($connString)
                    $conn.open()
                    $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn);
                    $data = $cmd.ExecuteReader()
                    $dt = New-Object "System.Data.DataTable"
                    $dt.Load($data)
                    $conn.Close()
                    $conn.Dispose()
                    return $dt
                }
            }
            catch {
                Stop-Function -Message "Can't establish local DAC connection." -Target $server -InnerErrorRecord $_
                return
            }

            if ($server.IsClustered -and $dacEnabled -eq $false) {
                If ($Pscmdlet.ShouldProcess($server.Name, "Disabling DAC on clustered instance.")) {
                    Write-Message -Level Verbose -Message "Setting DAC config back to 0."
                    $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
                    $server.Configuration.Alter()
                }
            }

            $decryptedLogins = New-Object "System.Data.DataTable"
            [void]$decryptedLogins.Columns.Add("LinkedServer")
            [void]$decryptedLogins.Columns.Add("Login")
            [void]$decryptedLogins.Columns.Add("Password")


            # Go through each row in results
            foreach ($login in $logins) {
                # decrypt the password using the service master key and the extracted IV
                $decryptor.Padding = "None"
                $decrypt = $decryptor.Createdecryptor($serviceKey, $login.iv)
                $stream = New-Object System.IO.MemoryStream ( , $login.pass)
                $crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"

                $crypto.Write($login.pass, 0, $login.pass.Length)
                [byte[]]$decrypted = $stream.ToArray()

                # convert decrypted password to unicode
                $encode = New-Object System.Text.UnicodeEncoding

                # Print results - removing the weird padding (8 bytes in the front, some bytes at the end)...
                # Might cause problems but so far seems to work.. may be dependant on SQL server version...
                # If problems arise remove the next three lines..
                $i = 8; foreach ($b in $decrypted) {if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) { $i -= 1; break; }; $i += 1; }
                $decrypted = $decrypted[8..$i]

                [void]$decryptedLogins.Rows.Add($($login.srvname), $($login.Name), $($encode.GetString($decrypted)))
            }
            return $decryptedLogins
        }

        function Copy-DbaLinkedServers {
            param (
                [string[]]$LinkedServer,
                [bool]$force
            )

            Write-Message -Level Verbose -Message "Collecting Linked Server logins and passwords on $($sourceServer.Name)."
            $sourcelogins = Get-LinkedServerLogins $sourceServer

            $serverlist = $sourceServer.LinkedServers

            if ($LinkedServer) {
                $serverlist = $serverlist | Where-Object Name -In $LinkedServer
            }
            if ($ExcludeLinkedServer) {
                $serverList = $serverlist | Where-Object Name -NotIn $ExcludeLinkedServer
            }

            foreach ($currentLinkedServer in $serverlist) {
                $provider = $currentLinkedServer.ProviderName
                try {
                    $destServer.LinkedServers.Refresh()
                    $destServer.LinkedServers.LinkedServerLogins.Refresh()
                }
                catch { }

                $linkedServerName = $currentLinkedServer.Name

                $copyLinkedServer = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $linkedServerName
                    Type              = "Linked Server"
                    Status            = $null
                    Notes             = $provider
                    DateTime          = [DbaDateTime](Get-Date)
                }

                # This does a check to warn of missing OleDbProviderSettings but should only be checked on SQL on Windows
                if ($destServer.Settings.OleDbProviderSettings.Name.Length -ne 0) {
                    if (!$destServer.Settings.OleDbProviderSettings.Name -contains $provider -and !$provider.StartsWith("SQLN")) {
                        $copyLinkedServer.Status = "Skipped"
                        $copyLinkedServer.Notes = "Already exists"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "$($destServer.Name) does not support the $provider provider. Skipping $linkedServerName."
                        continue
                    }
                }

                if ($destServer.LinkedServers[$linkedServerName] -ne $null) {
                    if (!$force) {
                        $copyLinkedServer.Status = "Skipped"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "$linkedServerName exists $($destServer.Name). Skipping."
                        continue
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($destination, "Dropping $linkedServerName")) {
                            if ($currentLinkedServer.Name -eq 'repl_distributor') {
                                Write-Message -Level Verbose -Message "repl_distributor cannot be dropped. Not going to try."
                                continue
                            }

                            $destServer.LinkedServers[$linkedServerName].Drop($true)
                            $destServer.LinkedServers.refresh()
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate: $linkedServerName."
                If ($Pscmdlet.ShouldProcess($destination, "Migrating $linkedServerName")) {
                    try {
                        $sql = $currentLinkedServer.Script() | Out-String
                        Write-Message -Level Debug -Message $sql

                        if ($UpgradeSqlClient -and $sql -match "sqlncli") {
                            $newstring = "sqlncli$($destServer.VersionMajor)"
                            Write-Message -Level Verbose -Message "Changing sqlncli to $newstring"
                            $sql = $sql -replace ("sqlncli[0-9]+", $newstring)
                        }

                        $destServer.Query($sql)
                        $destServer.LinkedServers.Refresh()
                        Write-Message -Level Verbose -Message "$linkedServerName successfully copied."

                        $copyLinkedServer.Status = "Successful"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    catch {
                        $copyLinkedServer.Status = "Failed"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue adding linked server $destServer." -Target $linkedServerName -InnerErrorRecord $_
                        $skiplogins = $true
                    }
                }

                if ($skiplogins -ne $true) {
                    $destlogins = $destServer.LinkedServers[$linkedServerName].LinkedServerLogins
                    $lslogins = $sourcelogins | Where-Object { $_.LinkedServer -eq $linkedServerName }

                    foreach ($login in $lslogins) {
                        if ($Pscmdlet.ShouldProcess($destination, "Migrating $($login.Login)")) {
                            $currentlogin = $destlogins | Where-Object { $_.RemoteUser -eq $login.Login }

                            $copyLinkedServer.Type = $login.Login

                            if ($currentlogin.RemoteUser.length -ne 0) {
                                try {
                                    $currentlogin.SetRemotePassword($login.Password)
                                    $currentlogin.Alter()

                                    $copyLinkedServer.Status = "Successful"
                                    $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                                catch {
                                    $copyLinkedServer.Status = "Failed"
                                    $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                    Stop-Function -Message "Failed to copy login." -Target $login -InnerErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($SourceSqlCredential.username -ne $null) {
            Write-Message -Level Verbose -Message "You are using a SQL Credential. Note that this script requires Windows Administrator access on the source server. Attempting with $($SourceSqlCredential.Username)."
        }

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.Name
        $destination = $destServer.Name

        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting." -Target $sourceServer
            return
        }
        if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $destination. Quitting." -Target $destServer
            return
        }

        Write-Message -Level Verbose -Message "Getting NetBios name for $source."
        $sourceNetBios = Resolve-NetBiosName $sourceserver

        Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $source."
        try {
            Invoke-Command2 -Raw -Credential $Credential -ComputerName $sourceNetBios -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Can't connect to registry on $source." -Target $sourceNetBios -ErrorRecord $_
            return
        }

        # Magic happens here
        Copy-DbaLinkedServers $LinkedServer -Force:$force
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlLinkedServer
    }
}
