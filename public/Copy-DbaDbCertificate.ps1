function Copy-DbaDbCertificate {
    <#
    .SYNOPSIS
        Copies database-level certificates from source SQL Server to destination servers, including private keys and master key dependencies.

    .DESCRIPTION
        Transfers database certificates between SQL Server instances by backing them up from source databases and restoring them to matching databases on destination servers. This function handles the complex certificate migration process that's essential when moving databases with Transparent Data Encryption (TDE) or other certificate-based security features.

        The function backs up each certificate with its private key to a shared network path accessible by both source and destination SQL Server service accounts. It automatically creates database master keys on the destination if they don't exist and you provide the MasterKeyPassword parameter. Existing certificates are skipped unless you use the Force parameter to overwrite them.

        This is particularly useful for database migration projects, disaster recovery setup, and maintaining encryption consistency across environments where manual certificate management would be time-consuming and error-prone.

    .PARAMETER Source
        The source SQL Server instance containing the database certificates to copy. Requires sysadmin privileges to access certificate metadata and backup operations.
        Use this to specify where the certificates currently exist that need to be migrated to other servers.

    .PARAMETER SourceSqlCredential
        Alternative credentials for connecting to the source SQL Server instance. Use this when the current Windows user lacks sufficient privileges or when connecting with SQL authentication.
        Essential for cross-domain scenarios or when running under service accounts that don't have source server access.

    .PARAMETER Destination
        The destination SQL Server instance(s) where certificates will be restored. Accepts multiple servers for bulk certificate deployment.
        Requires sysadmin privileges to create master keys and restore certificates to matching databases.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for connecting to destination SQL Server instance(s). Required when destination servers are in different domains or when using SQL authentication.
        Must have permissions to create database master keys and restore certificates in target databases.

    .PARAMETER Database
        Specifies which databases to include when copying certificates. Only certificates from these databases will be migrated to matching databases on destination servers.
        Use this to limit certificate copying to specific databases rather than processing all databases with certificates.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from certificate copying operations. Certificates in these databases will be skipped even if they exist on the source.
        Useful when you want to copy most database certificates but exclude system databases or specific application databases.

    .PARAMETER Certificate
        Specifies which certificates to copy by name. Only these named certificates will be processed across all included databases.
        Use this to migrate specific certificates like TDE certificates while leaving other database certificates untouched.

    .PARAMETER ExcludeCertificate
        Excludes specific certificates from the copying process by name. These certificates will be skipped in all databases.
        Commonly used to exclude system-generated certificates or certificates that should remain environment-specific.

    .PARAMETER SharedPath
        Network path where certificate backup files will be temporarily stored during the copy operation. Both source and destination SQL Server service accounts must have full access to this location.
        Required because certificates cannot be directly transferred between instances and must be backed up to disk first.

    .PARAMETER EncryptionPassword
        Secure password used to encrypt the private key during certificate backup operations. If not provided, a random password is generated automatically.
        Specify this when you need consistent encryption passwords across multiple certificate operations or for compliance requirements.

    .PARAMETER DecryptionPassword
        Password required to decrypt the private key when restoring certificates to destination databases. Must match the password used when the certificate was originally backed up.
        Use this when copying certificates that were previously backed up with a specific encryption password.

    .PARAMETER MasterKeyPassword
        Password for creating database master keys on destination servers when they don't exist. Required for certificates that use master key encryption.
        Essential for TDE scenarios where certificates depend on database master keys for private key protection.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Overwrites existing certificates on destination servers that have the same names as source certificates. Without this switch, existing certificates are skipped.
        Use this when refreshing certificates during disaster recovery or when certificates need to be updated with new keys.

    .NOTES
        Tags: Migration, Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDbCertificate


    .OUTPUTS
        PSCustomObject

        Returns one object per certificate copy operation attempted, regardless of success or failure. Each object represents the result of copying a single certificate from a source database to a destination database.

        Default display properties (via Select-DefaultView with TypeName MigrationObject):
        - DateTime: The date and time when the copy operation occurred
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - Name: The name of the certificate being copied
        - Type: Always "Database Certificate" indicating the object type
        - Status: The result of the operation (Successful, Skipped, or Failed)
        - Notes: Additional information about the operation (reason for skipping, error details, etc.)

        Additional properties available (not shown by default):
        - SourceDatabase: The name of the source database containing the certificate
        - SourceDatabaseID: The ID of the source database
        - DestinationDatabase: The name of the destination database where the certificate was restored
        - DestinationDatabaseID: The ID of the destination database

        All properties from the PSCustomObject are accessible via Select-Object * even though only default properties display without explicitly using Select-Object.

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

                                        # The exported files are only readable by the source instance account
                                        # But for the restore they need to be readable by the targe instance account
                                        # Current solution is to try to make them readable to everyone and remove them after the restore
                                        foreach ($filePath in $export.Path, $export.Key) {
                                            try {
                                                $acl = Get-Acl $filePath
                                                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "ReadAndExecute", "None", "None", "Allow")
                                                $acl.SetAccessRule($accessRule)
                                                Set-Acl -Path $filePath -AclObject $acl
                                            } catch {
                                                Write-Message -Level Verbose -Message "Failed to set permission for [$filePath]: $_"
                                            }
                                        }
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
                                $copyDbCertificateStatus.Status = "Failed"
                                $copyDbCertificateStatus.Notes = $PSItem
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                if ($usingtempfiles) {
                                    Write-Message -Level Verbose -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name). Note that $($export.Path) and $($export.Key) already existed so we tried to use them. If this is an issue, please move or rename both files and try again."
                                } else {
                                    Write-Message -Level Verbose -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name) | $PSItem"
                                }
                            } finally {
                                if ($export.Path -and -not $usingtempfiles) {
                                    $null = Remove-Item -Path $export.Path -Force -ErrorAction SilentlyContinue
                                }
                                if ($export.Key -and -not $usingtempfiles) {
                                    $null = Remove-Item -Path $export.Key -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}