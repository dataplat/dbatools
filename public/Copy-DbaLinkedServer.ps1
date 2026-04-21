function Copy-DbaLinkedServer {
    <#
    .SYNOPSIS
        Migrates linked servers and their authentication credentials from one SQL Server instance to another

    .DESCRIPTION
        Migrates SQL Server linked servers including all authentication credentials and connection settings from a source instance to one or more destination instances. The function preserves usernames and passwords by using password decryption techniques, eliminating the need to manually recreate linked server configurations and re-enter sensitive credentials.

        This is particularly useful during server migrations, disaster recovery scenarios, or when consolidating environments where maintaining external data connections is critical. The function handles various provider types and can optionally upgrade older SQL Client providers to current versions during migration.

        When upgrading from older versions to SQL Server 2025+, MSOLEDBSQL is changed to MSOLEDBSQL19 and provider string for encrypt and trustservercertificate settings is added if not already included to ensure compatibility with the breaking changes in the new driver.

        Credit: Password decryption techniques provided by Antti Rantasaari (NetSPI, 2014) - https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/

    .PARAMETER Source
        Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target OS using alternative credentials. Accepts credential objects (Get-Credential)

        Only used when passwords are being exported, as it requires access to the Windows OS via PowerShell remoting to decrypt the passwords.

    .PARAMETER LinkedServer
        Specifies which linked servers to copy from the source instance. Accepts an array of linked server names.
        Use this when you only need to migrate specific linked servers rather than all of them.
        If omitted, all linked servers from the source will be copied to the destination.

    .PARAMETER ExcludeLinkedServer
        Specifies linked servers to skip during the copy operation. Accepts an array of linked server names.
        Use this when you want to copy most linked servers but exclude problematic ones or those that shouldn't be migrated.
        This parameter is ignored if LinkedServer is specified.

    .PARAMETER UpgradeSqlClient
        Updates older SQL Server Native Client providers (SQLNCLI) to the newest version available on the destination server.
        Use this when migrating from older SQL Server versions to ensure linked servers use current client libraries.
        The function automatically detects and upgrades to the highest numbered SQLNCLI provider found on the destination.

    .PARAMETER ExcludePassword
        Copies linked server definitions without migrating stored passwords or sensitive authentication data.
        Use this in security-conscious environments where password decryption is restricted or when passwords should be manually reset after migration.
        Linked servers will be created but authentication credentials will need to be reconfigured.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Drops and recreates linked servers that already exist on the destination instance.
        Use this when you need to overwrite existing linked server configurations with updated settings from the source.
        Without this parameter, existing linked servers on the destination are skipped to prevent accidental overwrites.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

     .OUTPUTS
         PSCustomObject

         Returns one object per linked server processed. The object contains migration status information for each linked server and its logins that were copied from source to destination.

         Default display properties (via Select-DefaultView):
         - DateTime: Timestamp when the linked server was processed (DbaDateTime object)
         - SourceServer: Name of the source SQL Server instance
         - DestinationServer: Name of the destination SQL Server instance
         - Name: Name of the linked server being migrated
         - Type: Initially "Linked Server", then set to the remote login identity being configured
         - Status: Status of the operation (Successful, Skipped, or Failed)
         - Notes: Provider name, or reason for skip/failure (e.g., "Missing provider", "Already exists on destination", or error message)
    .NOTES
        Tags: WSMan, Migration, LinkedServer
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers
        Limitations: This just copies the SQL portion. It does not copy files (i.e. a local SQLite database, or Microsoft Access DB), nor does it configure ODBC entries.

    .LINK
        https://dbatools.io/Copy-DbaLinkedServer

    .EXAMPLE
        PS C:\> Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster

        Copies all SQL Server Linked Servers on sqlserver2014a to sqlcluster. If Linked Server exists on destination, it will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster -LinkedServer SQL2K5,SQL2k -Force

        Copies over two SQL Server Linked Servers (SQL2K and SQL2K2) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [PSCredential]$Credential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [switch]$UpgradeSqlClient,
        [switch]$ExcludePassword,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaLinkedServer is only supported on Windows"
            return
        }
        $null = Test-ElevationRequirement -ComputerName $Source.ComputerName

        if ($Force) { $ConfirmPreference = 'none' }

        function Copy-DbaLinkedServers {
            param (
                [string[]]$LinkedServer,
                [bool]$force
            )

            Write-Message -Level Verbose -Message "Collecting Linked Server logins and passwords on $($sourceServer.Name)."
            if ($ExcludePassword) {
                $sourcelogins = @()
                foreach ($svr in $sourceServer.LinkedServers) {
                    $sourcelogins += [PSCustomObject]@{
                        Name     = $sourcelogin.Name
                        Identity = $sourcelogin.LinkedServerLogins.RemoteUser
                        Password = $null
                    }
                }
            } else {
                $sourcelogins = Get-DecryptedObject -SqlInstance $sourceServer -Credential $Credential -Type LinkedServer -EnableException:$EnableException
            }

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
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }

                $linkedServerName = $currentLinkedServer.Name
                $linkedServerProductName = $currentLinkedServer.ProductName
                $linkedServerDataSource = $currentLinkedServer.DataSource

                $copyLinkedServer = [PSCustomObject]@{
                    SourceServer      = $sourceServer.DomainInstanceName
                    DestinationServer = $destServer.DomainInstanceName
                    Name              = $linkedServerName
                    ProductName       = $linkedServerProductName
                    DataSource        = $linkedServerDataSource
                    Type              = "Linked Server"
                    Status            = $null
                    Notes             = $provider
                    DateTime          = [DbaDateTime](Get-Date)
                }

                # This does a check to warn of missing OleDbProviderSettings but should only be checked on SQL on Windows
                if ($destServer.Settings.OleDbProviderSettings.Name.Length -ne 0) {
                    if ($destServer.VersionMajor -ge 17 -and $provider -eq "MSOLEDBSQL") {
                        # Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
                        Write-Message -Level Verbose -Message "Upgrading provider from MSOLEDBSQL to MSOLEDBSQL19 to ensure compatibility with SQL Server 2025+."
                        $provider = "MSOLEDBSQL19"
                    }
                    if (-not ($destServer.Settings.OleDbProviderSettings.Name -contains $provider) -and -not ($provider.StartsWith("SQLN"))) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$($destServer.Name) does not support the $provider provider. Skipping $linkedServerName.")) {
                            $copyLinkedServer.Status = "Skipped"
                            $copyLinkedServer.Notes = "Missing provider"
                            $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "$($destServer.Name) does not support the $provider provider. Skipping $linkedServerName."
                        }
                        continue
                    }
                }

                if ($null -ne $destServer.LinkedServers[$linkedServerName]) {
                    if (!$force) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Linked server $linkedServerName exists on $($destServer.Name)")) {
                            $copyLinkedServer.Status = "Skipped"
                            $copyLinkedServer.Notes = "Already exists on destination"
                            $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Linked server $linkedServerName exists on $($destServer.Name)."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $linkedServerName")) {
                            try {
                                if ($currentLinkedServer.Name -eq 'repl_distributor') {
                                    Write-Message -Level Verbose -Message "repl_distributor cannot be dropped. Not going to try."
                                    continue
                                }
                                $destServer.LinkedServers[$linkedServerName].Drop($true)
                                $destServer.LinkedServers.refresh()
                            } catch {
                                $copyLinkedServer.Status = "Failed"
                                $copyLinkedServer.Notes = "Issue dropping linked server $linkedServerName on $destinstance | $PSItem"
                                $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping linked server $linkedServerName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate: $linkedServerName."
                If ($Pscmdlet.ShouldProcess($destinstance, "Migrating $linkedServerName")) {
                    try {
                        $sql = $currentLinkedServer.Script() | Out-String
                        Write-Message -Level Debug -Message $sql

                        if ($UpgradeSqlClient -and $sql -match "sqlncli") {
                            $destProviders = $destServer.Settings.OleDbProviderSettings | Where-Object { $_.Name -like 'SQLNCLI*' }
                            $newProvider = $destProviders | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name

                            Write-Message -Level Verbose -Message "Changing sqlncli to $newProvider"
                            $sql = $sql -replace ("sqlncli[0-9]+", $newProvider)
                        }

                        if ($provider -eq "MSOLEDBSQL19") {
                            # Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
                            $providerString = $currentLinkedServer.ProviderString
                            if ($providerString) {
                                if ($providerString -notmatch "Encrypt\s*=\s*Optional" -and $providerString -notmatch "TrustServerCertificate\s*=\s*Yes") {
                                    Write-Message -Level Warning -Message "Provider string currently set to '$providerString', so will not change it. Please verify that it includes 'Encrypt=Optional;TrustServerCertificate=Yes' to ensure connectivity."
                                } else {
                                    Write-Message -Level Verbose -Message "Provider string already includes encrypt and trustservercertificate settings, so not modifying it."
                                }
                            } else {
                                Write-Message -Level Verbose -Message "Provider string is empty. Adding 'Encrypt=Optional;TrustServerCertificate=Yes' to provider string for MSOLEDBSQL19."
                                $sql = $sql -replace "@provider=N'MSOLEDBSQL'", "@provider=N'MSOLEDBSQL19', @provstr=N'Encrypt=Optional;TrustServerCertificate=Yes'"
                            }
                        }

                        $null = $destServer.Query($sql)

                        if ($copyLinkedServer.ProductName -eq 'SQL Server' -and $copyLinkedServer.Name -ne $copyLinkedServer.DataSource) {
                            $sql2 = "EXEC sp_setnetname '$($copyLinkedServer.Name)', '$($copyLinkedServer.DataSource)'; "
                            $destServer.Query($sql2)
                        }

                        $destServer.LinkedServers.Refresh()
                        Write-Message -Level Verbose -Message "$linkedServerName successfully copied."
                        $copyLinkedServer.Status = "Successful"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyLinkedServer.Notes = (Get-ErrorMessage -Record $_)
                        $copyLinkedServer.Status = "Failed"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating linked server $linkedServerName on $destinstance | $PSItem"
                        continue
                    }
                }

                $destlogins = $destServer.LinkedServers[$linkedServerName].LinkedServerLogins
                $lslogins = $sourcelogins | Where-Object { $_.Name -eq $linkedServerName }

                foreach ($login in $lslogins) {
                    $currentlogin = $destlogins | Where-Object { $_.RemoteUser -eq $login.Identity }

                    $copyLinkedServer.Type = $login.Identity

                    if ($currentlogin.RemoteUser.length -ne 0) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Migrating linked server identity $($login.Identity)")) {
                            try {
                                if ($login.Password) {
                                    $currentlogin.SetRemotePassword($login.Password)
                                    $currentlogin.Alter()
                                }

                                $copyLinkedServer.Status = "Successful"
                                $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                $copyLinkedServer.Status = "Failed"
                                $copyLinkedServer.Notes = (Get-ErrorMessage -Record $_)
                                $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue creating linked server identity for $($login.Identity) on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }
            }
        }

        if ($null -ne $SourceSqlCredential.Username) {
            Write-Message -Level Verbose -Message "You are using a SQL Credential. Note that this script requires Windows Administrator access on the source server. Attempting with $($SourceSqlCredential.Username)."
        }

        try {
            # Do we need a dedicated admin connection to the source for password retrieval?
            # If passwords are excluded, we don't need a DAC
            if ($ExcludePassword) { $dacNeeded = $false } else { $dacNeeded = $true }

            # Do we have a dedicated admin connection already?
            $dacConnected = $Source.Type -eq "Server" -and $Source.InputObject.ConnectionContext.ServerInstance -match "^ADMIN:"

            $dacOpened = $false
            if ($dacNeeded) {
                if ($dacConnected) {
                    Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval."
                    $sourceServer = $Source.InputObject
                } else {
                    Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval."
                    try {
                        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -DedicatedAdminConnection
                        $dacOpened = $true
                    } catch {
                        Write-Message -Level Warning -Message "Unable to open dedicated admin connection on $Source. Passwords will not be copied. To suppress this warning, use -ExcludePassword."
                        $ExcludePassword = $true
                        $dacNeeded = $false
                    }
                }
            }
            if (-not $dacNeeded) {
                Write-Message -Level Verbose -Message "Opening or reusing normal connection because passwords are excluded."
                $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            }
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destinstance" -Target $destServer -Continue
            }

            # Magic happens here
            Copy-DbaLinkedServers $LinkedServer -Force:$force
        }
    }
    end {
        if ($dacOpened) {
            $null = $sourceServer | Disconnect-DbaInstance -WhatIf:$false
        }
    }
}