function Copy-DbaDbCertificate {
    <#
    .SYNOPSIS
        Copy-DbaDbCertificate migrates certificates from one SQL Server to another.

    .DESCRIPTION
        By default, all certificates are copied.

        If the certificate already exists on the destination, it will be skipped unless -Force is used.

        This script does not yet copy dependencies or dependent objects.

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

    .PARAMETER Certificate
        The certificate(ies) to process. This list is auto-populated from the server. If unspecified, all certificates will be processed.

    .PARAMETER ExcludeCertificate
        The certificate(ies) to exclude. This list is auto-populated from the server.

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
        PS C:\> Copy-DbaDbCertificate -Source mssql1 -Destination mssql2

        Copies all certificates from mssql1 to mssql2 using Windows credentials. If certificates with the same name exist on mssql2, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaDbCertificate -Source mssql1 -Destination mssql2 -Certificate dbname.certificatename, dbname3.anothercertificate -SourceSqlCredential $cred -Force

        Copies two certificates, the dbname.certificatename and dbname3.anothercertificate from mssql1 to mssql2 using SQL credentials for mssql1 and Windows credentials for mssql2. If certificates with the same name exist on mssql2, they will be skipped.

        In this example, anothercertificate will be copied to the dbname3 database on the server mssql2.

    .EXAMPLE
        PS C:\> Copy-DbaDbCertificate -Source mssql1 -Destination mssql2 -WhatIf -Force

        Shows what would happen if the command were executed using force.

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
                SqlInstance        = $Source
                SqlCredential      = $SourceSqlCredential
                Database           = $Database
                ExcludeDatabase    = $ExcludeDatabase
                Certificate        = $Certificate
                EnableException    = $true
            }
            # Get presumably user certs, no way to tell if its a system object
            $sourcecertificates = Get-DbaDbCertificate @parms | Where-Object Name -notlike "#*" | Where-Object Name -notin $ExcludeCertificate
            $dbsnames = $sourcecertificates.Parent.Name | Select-Object -Unique
            $server = ($sourcecertificates | Select-Object -First 1).Parent.Parent
            $serviceAccount = $server.ServiceAccount
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
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
        # THIS MAKES ASSUMPTIONS ABOUT THE CERTIFICATE THAT ITS ENCRYPTED BY A MASTER KEY
        # FOR START-DBAMIGRATION, IT NEEDS TO JUST BE COPY-DBADBMASTER

        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $serviceAccount = $destserver.ServiceAccount

            If (-not (Test-DbaPath -SqlInstance $destServer -Path $SharedPath)) {
                Stop-Function -Message "The SQL Server service account ($serviceAccount) for $destinstance does not have access to $SharedPath" -Continue
            }

            if (($sourcecertificates | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
                $masterkey = Get-DbaDbMasterKey -SqlInstance $db.Parent -Database master
                if (-not $masterkey) {
                    Write-Message -Level Verbose -Message "master key not found, seeing if MasterKeyPassword was specified"
                    if ($MasterKeyPassword) {
                        Write-Message -Level Verbose -Message "master key not found, creating one"
                        try {
                            $params = @{
                                SqlInstance     = $destServer
                                SecurePassword  = $MasterKeyPassword
                                EnableException = $true
                            }
                            $masterkey = New-DbaServiceMasterKey @params
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                        }
                    } else {
                        return $PSBoundParameters
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
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                            }

                        } else {
                            $domasterkeypasswordmessage = $true
                        }
                    }

                    foreach ($cert in $sourcerts) {
                        $certname = $cert.Name
                        Write-Message -Level VeryVerbose -Message "Processing $certname on $dbName"

                        $copyDbCertificateStatus = [pscustomobject]@{
                            SourceServer        = $Source
                            SourceDatabase      = $dbName
                            DestinationServer   = $destServer.Name
                            DestinationDatabase = $dbName
                            type                = "Database Certificate"
                            Name                = $certname
                            Status              = $null
                            Notes               = $null
                            DateTime            = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }

                        if ($domasterkeymessage) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = $domasterkeymessage
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message $domasterkeymessage
                            continue
                        }

                        if ($domasterkeypasswordmessage) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = "Master service key not found and MasterKeyPassword not provided for auto-creation"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Master service key not found and MasterKeyPassword not provided for auto-creation"
                            continue
                        }
                        $null = $db.Refresh()
                        if ($db.Certificates.Name -contains $certname) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = "Already exists on destination"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Certificate $certname exists at destination in the $dbName database"
                            continue
                        }

                        if ($Pscmdlet.ShouldProcess($destinstance.Name, "Copying certificate $certname from database.")) {
                            try {
                                # Back up certificate
                                $null = $db.Refresh()
                                $params = @{
                                    SqlInstance        = $cert.Parent.Parent
                                    Database           = $db.Name
                                    Certificate        = $certname
                                    Path               = $SharedPath
                                    EnableException    = $true
                                    Suffix             = $null
                                    EncryptionPassword = $backupEncryptionPassword
                                    DecryptionPassword = $DecryptionPassword
                                }
                                Write-Message -Level Verbose -Message "Backing up certificate $cername for $($dbName) on $($server.Name)"
                                $export = Backup-DbaDbCertificate @params

                                # Restore certificate
                                $params = @{
                                    SqlInstance        = $db.Parent
                                    Database           = $db.Name
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
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name)" -Target $certname -ErrorRecord $_
                            }
                        }
                    }
                }
            }
        }
    }
}