function Start-DbaDbEncryption {
    <#
    .SYNOPSIS
        Combokill

    .DESCRIPTION
        Combokill

        protected by the master key

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database that will be encrypted.

    .PARAMETER EncryptorName
        XYZ

    .PARAMETER EncryptorType
        Type of Encryptor - either Asymmetric or Certificate

    .PARAMETER MasterKeySecurePassword
        XYZ

    .PARAMETER BackupSecurePassword
        XYZ

    .PARAMETER Force
        XYZ

    .PARAMETER All
        XYZ

    .PARAMETER BackupPath
        The path where its all backed up

    .PARAMETER CertificateSubject
        Optional subject to create the certificate.

    .PARAMETER CertificateStartDate
        Optional secure string used to create the certificate.

    .PARAMETER CertificateExpirationDate
        Optional secure string used to create the certificate.

    .PARAMETER CertificateActiveForServiceBrokerDialog
        Optional secure string used to create the certificate.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaDbEncryption

    .EXAMPLE
        PS C:\> Start-DbaDbEncryption -SqlInstance Server1

        xyz

    .EXAMPLE
        PS C:\> Start-DbaDbEncryption -SqlInstance Server1 -Database db1 -Confirm:$false

        xyz

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$EncryptorName,
        [ValidateSet("AsymmetricKey", "Certificate")]
        [string]$EncryptorType = "Certificate",
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [Parameter(Mandatory)]
        [Security.SecureString]$MasterKeySecurePassword,
        [string]$CertificateSubject,
        [datetime]$CertificateStartDate = (Get-Date),
        [datetime]$CertificateExpirationDate = (Get-Date).AddYears(5),
        [switch]$CertificateActiveForServiceBrokerDialog,
        [Parameter(Mandatory)]
        [Security.SecureString]$BackupSecurePassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$All,
        [switch]$EnableException
    )
    process {
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or pipe in an InputObject from Get-DbaDatabase"
            return
        }

        if ($SqlInstance) {
            if (-not $Database -and -not $ExcludeDatabase -and -not $All) {
                Stop-Function -Message "You must specify Database, ExcludeDatabase or All when using SqlInstance"
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $param = @{
                SqlInstance     = $SqlInstance
                SqlCredential   = $SqlCredential
                Database        = $Database
                ExcludeDatabase = $ExcludeDatabase
            }
            $InputObject += Get-DbaDatabase @param | Where-Object Name -NotIn 'master', 'model', 'tempdb', 'msdb', 'resource'
        }

        $PSDefaultParameterValues["Connect-DbaInstance:Verbose"] = $false
        foreach ($db in $InputObject) {
            try {
                $server = $db.Parent
                # refresh in case we have a stale database
                $null = $db.Refresh()
                $null = $server.Refresh()

                if ($db.EncryptionEnabled) {
                    Stop-Function -Message "Database $($db.Name) on $($server.Name) is already encrypted" -Continue
                }
                $stepCounter = 0
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Processing $($db.Name)"

                # Ensure a database master key exists in the master database
                Write-Message -Level Verbose -Message "Ensure a database master key exists in the master database for $($server.Name)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensure a database master key exists in the master database for $($server.Name)"
                $masterkey = Get-DbaDbMasterKey -SqlInstance $server -Database master

                if (-not $masterkey) {
                    Write-Message -Level Verbose -Message "master key not found, creating one"
                    $params = @{
                        SqlInstance     = $server
                        SecurePassword  = $MasterKeySecurePassword
                        EnableException = $true
                    }
                    $masterkey = New-DbaServiceMasterKey @params

                    # Back up master key
                    $params = @{
                        SqlInstance     = $server
                        Database        = "master"
                        Path            = $BackupPath
                        EnableException = $true
                        SecurePassword  = $BackupSecurePassword
                    }
                    $null = $server.Databases["master"].Refresh()
                    Write-Message -Level Verbose -Message "Backing up master key"
                    $null = Backup-DbaDbMasterKey @params
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Processing EncryptorType for $($db.Name) on $($server.Name)"
                if ($EncryptorType -eq "Certificate") {
                    if ($EncryptorName) {
                        $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -eq $EncryptorName
                    } else {
                        $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -NotMatch "##"
                    }

                    if ($mastercert.Count -gt 1) {
                        Stop-Function -Message "More than one certificate found on $($server.Name), please specify an EncryptorName" -Continue
                    }

                    if (-not $mastercert) {
                        Write-Message -Level Verbose -Message "master cert not found, creating one"
                        $params = @{
                            SqlInstance                  = $server
                            Database                     = "master"
                            StartDate                    = $CertificateStartDate
                            ExpirationDate               = $CertificateExpirationDate
                            ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                            EnableException              = $true
                        }
                        if ($CertificateSubject) {
                            $params.Subject = $CertificateSubject
                        }
                        $mastercert = New-DbaDbCertificate @params

                        # Back up certificate
                        $null = $server.Databases["master"].Refresh()
                        $params = @{
                            SqlInstance        = $server
                            Database           = "master"
                            Certificate        = $mastercert.Name
                            Path               = $BackupPath
                            EnableException    = $true
                            EncryptionPassword = $BackupSecurePassword
                        }
                        Write-Message -Level Verbose -Message "Backing up master certificate"
                        $null = Backup-DbaDbCertificate @params
                    } else {
                        Write-Message -Level Verbose -Message "master cert found on $($server.Name)"
                    }

                    if (-not $EncryptorName) {
                        Write-Message -Level Verbose -Message "Getting EncryptorName from master cert"
                        $EncryptorName = $mastercert.Name
                    }
                } else {
                    $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master

                    if (-not $masterasym) {
                        Write-Message -Level Verbose -Message "Asymmetric key not found, creating one"
                        $params = @{
                            SqlInstance     = $server
                            Database        = "master"
                            EnableException = $true
                        }
                        $masterasym = New-DbaDbAsymmetricKey @params
                        $null = $server.Refresh()
                        $null = $server.Databases["master"].Refresh()
                    } else {
                        Write-Message -Level Verbose -Message "master asymmetric key found on $($server.Name)"
                    }

                    if (-not $EncryptorName) {
                        Write-Message -Level Verbose -Message "Getting EncryptorName from master asymmetric key"
                        $EncryptorName = $masterasym.Name
                    }
                }

                Write-Message -Level Verbose -Message "Using EncryptorName '$EncryptorName'"
                # Create a database master key in the target database
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating database master key for $($db.Name) on $($server.Name)"

                $null = $server.Databases["master"].Refresh()
                $dbmasterkey = $db | Get-DbaDbMasterKey

                if (-not $dbmasterkey) {
                    $params = @{
                        SqlInstance     = $server
                        Database        = $db.Name
                        SecurePassword  = $MasterKeySecurePassword
                        EnableException = $true
                    }

                    Write-Message -Level Verbose -Message "Creating master key in $($db.Name) on $($server.Name)"
                    $dbmasterkey = New-DbaDbMasterKey @params
                    $null = $db.Refresh()

                    # Back up master key
                    $params = @{
                        SqlInstance     = $server
                        Database        = $db.Name
                        Path            = $BackupPath
                        EnableException = $true
                        SecurePassword  = $BackupSecurePassword
                    }
                    Write-Message -Level Verbose -Message "Backing up master key for $($db.Name) on $($server.Name)"
                    $null = Backup-DbaDbMasterKey @params
                } else {
                    Write-Message -Level Verbose -Message "master key found in $($db.Name) on $($server.Name)"
                }

                # Create a database certificate or asymmetric key in the target database
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating a database certificate or asymmetric key in $($db.Name) on $($server.Name)"
                if ($EncryptorType -eq "Certificate") {
                    $dbcert = Get-DbaDbCertificate -SqlInstance $server -Database $db.Name

                    if (-not $dbcert) {
                        Write-Message -Level Verbose -Message "Cert not found for $($db.Name) on $($server.Name), creating one"
                        $params = @{
                            SqlInstance                  = $server
                            Database                     = $db.Name
                            StartDate                    = $CertificateStartDate
                            ExpirationDate               = $CertificateExpirationDate
                            ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                            EnableException              = $true
                        }

                        if ($CertificateSubject) {
                            $params.Subject = $CertificateSubject
                        }
                        $dbcert = New-DbaDbCertificate @params

                        # Back up certificate
                        $null = $db.Refresh()
                        $params = @{
                            SqlInstance        = $server
                            Database           = $db.Name
                            Certificate        = $dbcert.Name
                            Path               = $BackupPath
                            EnableException    = $true
                            EncryptionPassword = $BackupSecurePassword
                        }
                        Write-Message -Level Verbose -Message "Backing up certificate for $($db.Name) on $($server.Name)"
                        $null = Backup-DbaDbCertificate @params
                    } else {
                        Write-Message -Level Verbose -Message "Cert '$($dbcert.Name)' found in $($db.Name) on $($server.Name)"
                    }
                } else {
                    $dbasymkey = Get-DbaDbAsymmetricKey -SqlInstance $server -Database $db.Name

                    if (-not $dbasymkey) {
                        Write-Message -Level Verbose -Message "Asymmetric key not found for $($db.Name) on $($server.Name),creating one"
                        $params = @{
                            SqlInstance     = $server
                            Database        = $db.Name
                            EnableException = $true
                        }
                        $dbasymkey = New-DbaDbAsymmetricKey @params
                        $null = $db.Refresh()
                    }
                }
                $null = $db.Refresh()
                # Create a database encryption key in the target database
                # Enable database encryption on the target database

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating database encryption key in $($db.Name) on $($server.Name)"
                if ($db.HasDatabaseEncryptionKey) {
                    Write-Message -Level Verbose -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key"
                } else {
                    Write-Message -Level Verbose -Message "Creating new encryption key for $($db.Name) on $($server.Name) with EncryptorName $EncryptorName"
                    $null = $db | New-DbaDbEncryptionKey -EncryptorName $EncryptorName -Force:$force -EnableException
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling database encryption in $($db.Name) on $($server.Name)"
                Write-Message -Level Verbose -Message "Enabling encryption for $($db.Name) on $($server.Name)"
                $db | Enable-DbaDbEncryption -EncryptorName $EncryptorName -Force
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}