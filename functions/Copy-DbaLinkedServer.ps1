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
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [switch]$UpgradeSqlClient,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $null = Test-ElevationRequirement -ComputerName $Source.ComputerName
        function Copy-DbaLinkedServers {
            param (
                [string[]]$LinkedServer,
                [bool]$force
            )

            Write-Message -Level Verbose -Message "Collecting Linked Server logins and passwords on $($sourceServer.Name)."
            $sourcelogins = Get-DecryptedObject -SqlInstance $sourceServer -Type LinkedServer

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
                        $copyLinkedServer.Notes = "Missing provider"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "$($destServer.Name) does not support the $provider provider. Skipping $linkedServerName."
                        continue
                    }
                }

                if ($null -ne $destServer.LinkedServers[$linkedServerName]) {
                    if (!$force) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$linkedServerName exists $($destServer.Name). Skipping.")) {
                            $copyLinkedServer.Status = "Skipped"
                            $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            
                            Write-Message -Level Verbose -Message "$linkedServerName exists $($destServer.Name). Skipping."
                        }
                        continue
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $linkedServerName")) {
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
                    $lslogins = $sourcelogins | Where-Object { $_.Name -eq $linkedServerName }

                    foreach ($login in $lslogins) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Migrating $($login.Login)")) {
                            $currentlogin = $destlogins | Where-Object { $_.RemoteUser -eq $login.Identity }

                            $copyLinkedServer.Type = $login.Identity

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
        
        if ($null -ne $SourceSqlCredential.Username) {
            Write-Message -Level Verbose -Message "You are using a SQL Credential. Note that this script requires Windows Administrator access on the source server. Attempting with $($SourceSqlCredential.Username)."
        }
        try {
            Write-Message -Level Verbose -Message "Connecting to $Source"
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            return
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting." -Target $sourceServer
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
    }
    process {
        if (Test-FunctionInterrupt) { return }
        
        foreach ($destinstance in $Destination) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $destinstance"
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            }
            catch {
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
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlLinkedServer
    }
}