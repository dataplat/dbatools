function Copy-DbaDbCertificate {
    <#
    .SYNOPSIS
        Copies database-level certificates from source SQL Server to destination servers, including private keys and master key dependencies.

    .DESCRIPTION
        Transfers database certificates between SQL Server instances by backing them up from source databases and restoring them to matching databases on destination servers. This function handles the complex certificate migration process that's essential when moving databases with Transparent Data Encryption (TDE) or other certificate-based security features.

        The function backs up each certificate with its private key to a shared network path accessible by both source and destination SQL Server service accounts. It automatically creates database master keys on the destination if they don't exist and you provide the MasterKeyPassword parameter. Existing certificates are skipped unless you use the Force parameter to overwrite them.

        This is particularly useful for database migration projects, disaster recovery setup, and maintaining encryption consistency across environments where manual certificate management would be time-consuming and error-prone.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER Certificate
        The certificate(s) to process.

    .PARAMETER ExcludeCertificate
        The certificate(s) to exclude.

    .PARAMETER SharedPath
        Specifies the network location for the backup files. The SQL Server service accounts on both Source and Destination must have read/write permission to access this location.

    .PARAMETER EncryptionPassword
        A string value that specifies the secure password to encrypt the private key.

    .PARAMETER DecryptionPassword
        Secure string used to decrypt the private key.

    .PARAMETER MasterKeyPassword
        The password to encrypt the exported key. This must be a SecureString.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing certificates on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Migration, Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDbCertificate


    .EXAMPLE
        PS C:\> Copy-DbaDbCertificate -Source sql01 -Destination sql02 -EncryptionPassword $cred.Password -MasterKeyPassword $cred.Password -SharedPath \\nas\sql\shared

        Copies database certificates for matching databases on sql02 and creates master keys if needed

        Uses password from $cred object created by Get-Credential

    .EXAMPLE
        PS C:\> $params1 = @{
        >>      Source = "sql01"
        >>      Destination = "sql02"
        >>      EncryptionPassword = $passwd
        >>      MasterKeyPassword = $passwd
        >>      SharedPath = "\\nas\sql\shared"
        >>  }
        PS C:\> Copy-DbaDbCertificate @params1 -Confirm:$false -OutVariable results

        Copies database certificates for matching databases on sql02 and creates master keys if needed

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Certificate,
        [string[]]$ExcludeCertificate,
        [string]$SharedPath,
        [Security.SecureString]$MasterKeyPassword,
        [Security.SecureString]$EncryptionPassword,
        [Security.SecureString]$DecryptionPassword,
        [switch]$EnableException
    )
    begin {
        try {
            $parms = @{
                SqlInstance     = $Source
                SqlCredential   = $SourceSqlCredential
                Database        = $Database
                ExcludeDatabase = $ExcludeDatabase
                Certificate     = $Certificate
                EnableException = $true
            }
            # Get presumably user certs, no way to tell if its a system object
            $sourcecertificates = Get-DbaDbCertificate @parms | Where-Object { $PSItem.Name -notlike "#*" -and $PSItem.Name -notin $ExcludeCertificate }
            $dbsnames = $sourcecertificates.Parent.Name | Select-Object -Unique
            $server = ($sourcecertificates | Select-Object -First 1).Parent.Parent
            $serviceAccount = $server.ServiceAccount
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $PSItem -Target $Source
            return
        }

        if (-not $PSBoundParameter.EncryptionPassword) {
            $backupEncryptionPassword = Get-RandomPassword
        } else {
            $backupEncryptionPassword = $EncryptionPassword
        }

        If ($serviceAccount -and -not (Test-DbaPath -SqlInstance $Source -SqlCredential $SourceSqlCredential -Path $SharedPath)) {
            Stop-Function -Message "The SQL Server service account ($serviceAccount) for $Source does not have access to $SharedPath"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $PSItem -Target $destinstance -Continue
            }
            $serviceAccount = $destserver.ServiceAccount

            If (-not (Test-DbaPath -SqlInstance $destServer -Path $SharedPath)) {
                Stop-Function -Message "The SQL Server service account ($serviceAccount) for $destinstance does not have access to $SharedPath" -Continue
            }

            if (($sourcecertificates | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
                $masterkey = Get-DbaDbMasterKey -SqlInstance $destServer -Database master
                if (-not $masterkey) {
                    Write-Message -Level Verbose -Message "master key not found, seeing if MasterKeyPassword was specified"
                    if ($MasterKeyPassword) {
                        Write-Message -Level Verbose -Message "master key not found, creating one"
                        try {
                            $params = @{
                                SqlInstance     = $destServer
                                SecurePassword  = $MasterKeyPassword
                                Database        = "master"
                                EnableException = $true
                            }
                            $masterkey = New-DbaDbMasterKey @params
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $PSItem -Continue
                        }
                    } else {
                        Stop-Function -Message "Master service key not found on $destinstance and MasterKeyPassword not specified, so it cannot be created" -Continue
                    }
                }
                $null = $destServer.Databases["master"].Refresh()
            }

            $destdbs = $destServer.Databases | Where-Object Name -in $dbsnames

            foreach ($db in $destdbs) {
                $dbName = $db.Name
                $sourcerts = $sourcecertificates | Where-Object { $PSItem.Parent.Name -eq $db.Name }

                # Check for master key requirement
                if (($sourcerts | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
                    $masterkey = Get-DbaDbMasterKey -SqlInstance $db.Parent -Database $db.Name

                    if (-not $masterkey) {
                        Write-Message -Level Verbose -Message "Master key not found, seeing if MasterKeyPassword was specified"
                        if ($MasterKeyPassword) {
                            try {
                                $params = @{
                                    SqlInstance     = $destServer
                                    SecurePassword  = $MasterKeyPassword
                                    Database        = $db.Name
                                    EnableException = $true
                                }
                                $masterkey = New-DbaDbMasterKey @params
                                $domasterkeymessage = $false
                                $domasterkeypasswordmessage = $false
                            } catch {
                                $domasterkeymessage = "Master key auto-generation failure: $PSItem"
                                Stop-Function -Message "Failure" -ErrorRecord $PSItem -Continue
                            }

                        } else {
                            $domasterkeypasswordmessage = $true
                        }
                    }

                    foreach ($cert in $sourcerts) {
                        $certname = $cert.Name
                        Write-Message -Level VeryVerbose -Message "Processing $certname on $dbName"

                        $copyDbCertificateStatus = [PSCustomObject]@{
                            SourceServer          = $cert.Parent.Parent.Name
                            SourceDatabase        = $dbName
                            SourceDatabaseID      = $cert.Parent.ID
                            DestinationServer     = $destServer.Name
                            DestinationDatabase   = $dbName
                            DestinationDatabaseID = $db.ID
                            type                  = "Database Certificate"
                            Name                  = $certname
                            Status                = $null
                            Notes                 = $null
                            DateTime              = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                        }

                        if ($domasterkeymessage) {
                            if ($Pscmdlet.ShouldProcess($destServer.Name, $domasterkeymessage)) {
                                $copyDbCertificateStatus.Status = "Skipped"
                                $copyDbCertificateStatus.Notes = $domasterkeymessage
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message $domasterkeymessage
                            }
                            continue
                        }

                        if ($domasterkeypasswordmessage) {
                            if ($Pscmdlet.ShouldProcess($destServer.Name, "Master service key not found and MasterKeyPassword not provided for auto-creation")) {
                                $copyDbCertificateStatus.Status = "Skipped"
                                $copyDbCertificateStatus.Notes = "Master service key not found and MasterKeyPassword not provided for auto-creation"
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Master service key not found and MasterKeyPassword not provided for auto-creation"
                            }
                            continue
                        }
                        $null = $db.Refresh()
                        if ($db.Certificates.Name -contains $certname) {
                            if ($Pscmdlet.ShouldProcess($destServer.Name, "Certificate $certname exists at destination in the $dbName database")) {
                                $copyDbCertificateStatus.Status = "Skipped"
                                $copyDbCertificateStatus.Notes = "Already exists on destination"
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Certificate $certname exists at destination in the $dbName database"
                            }
                            continue
                        }

                        if ($Pscmdlet.ShouldProcess($destServer.Name, "Copying certificate $certname from database.")) {
                            try {
                                # Back up certificate
                                $null = $db.Refresh()
                                $params = @{
                                    SqlInstance        = $cert.Parent.Parent
                                    Database           = $db.Name
                                    Certificate        = $certname
                                    Path               = $SharedPath
                                    EnableException    = $true
                                    EncryptionPassword = $backupEncryptionPassword
                                    DecryptionPassword = $DecryptionPassword
                                }
                                Write-Message -Level Verbose -Message "Backing up certificate $cername for $($dbName) on $($server.Name)"
                                try {
                                    $tempPath = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.cer"
                                    $tempKey = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.pvk"

                                    if ((Test-DbaPath -SqlInstance $server -Path $tempPath) -and (Test-DbaPath -SqlInstance $server -Path $tempKey)) {
                                        $export = [PSCustomObject]@{
                                            Path = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.cer"
                                            Key  = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.pvk"
                                        }
                                        # if files exist, then try to be helpful, otherwise, it just kills the whole process
                                        # this workaround exists because if you rename the back file, you'll rename the cert on restore
                                        Write-Message -Level Verbose -Message "ATTEMPTING TO USE FILES THAT ALREADY EXIST: $tempPath and $tempKey"
                                        $usingtempfiles = $true
                                    } else {
                                        $export = Backup-DbaDbCertificate @params
                                    }
                                } catch {
                                    $copyDbCertificateStatus.Status = "Failed $PSItem"
                                    $copyDbCertificateStatus.Notes = $PSItem
                                    $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Failed to create certificate $certname for $dbName on $destinstance | $PSItem"
                                    continue
                                }

                                # Restore certificate
                                $params = @{
                                    SqlInstance        = $db.Parent
                                    Database           = $db.Name
                                    Name               = $export.Certificate
                                    Path               = $export.Path
                                    KeyFilePath        = $export.Key
                                    EnableException    = $true
                                    EncryptionPassword = $DecryptionPassword
                                    DecryptionPassword = $backupEncryptionPassword
                                }

                                $null = Restore-DbaDbCertificate @params
                                $copyDbCertificateStatus.Status = "Successful"
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } catch {
                                if ($export.Path) {
                                    $null = Remove-Item -Force $export.Path -ErrorAction SilentlyContinue
                                }
                                if ($export.Key) {
                                    $null = Remove-Item -Force $export.Key -ErrorAction SilentlyContinue
                                }
                                $copyDbCertificateStatus.Status = "Failed"
                                $copyDbCertificateStatus.Notes = $PSItem
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                if ($usingtempfiles) {
                                    Write-Message -Level Verbose -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name). Note that $($export.Path) and $($export.Key) already existed so we tried to use them. If this is an issue, please move or rename both files and try again."
                                } else {
                                    Write-Message -Level Verbose -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name) | $PSItem"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}