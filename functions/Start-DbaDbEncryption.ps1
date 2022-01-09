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
        Optional name to create the certificate. Defaults to database name.

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
        [string]$EncryptorType,
        [string[]]$Database,
        [string]$BackupPath,
        [Security.SecureString]$MasterKeySecurePassword,
        [string]$CertificateSubject,
        [datetime]$CertificateStartDate = (Get-Date),
        [datetime]$CertificateExpirationDate = $StartDate.AddYears(5),
        [switch]$CertificateActiveForServiceBrokerDialog,
        [Security.SecureString]$CertificateSecurePassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            if (-not $Database -and -not $ExcludeDatabase -and -not $All) {
                Stop-Function -Message "You must specify Database, ExcludeDatabase or All when using SqlInstance"
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $param = @{
                SqlInstance = $SqlInstance
                SqlCredential = $SqlCredential
                Database      = $Database
                ExcludeDatabase = $ExcludeDatabase
            }
            $InputObject += = Get-DbaDatabase @param
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $null = $db.Refresh()
            $null = $server.Refresh()

            # Ensure a database master key exists in the master database
            $masterkey = Get-DbaDbMasterKey -SqlInstance $server -Database master
            if (-not $masterkey) {
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
                    Path            = $BakupPath
                    EnableException = $true
                    SecurePassword  = $MasterKeySecurePassword
                }
                $null = Backup-DbaDbMasterKey @params
            }

            if ($EncryptorType -eq "Certificate") {
                $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -notmatch "##"

                if ($mastercert.Count -gt 1) {
                    # Stop-Function
                }

                if (-not $mastercert) {
                    $params = @{
                        SqlInstance                  = $server
                        Database                     = "master"
                        StartDate                    = $CertificateStartDate
                        Subject                      = $CertificateSubject
                        ExpirationDate               = $CertificateExpirationDate
                        ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                        SecurePassword               = $CertificateSecurePassword
                        EnableException              = $true
                    }
                    $mastercert = New-DbaDbCertificate @params
                }
            } else {
                $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master

                if (-not $masterasym) {
                    $params = @{
                        SqlInstance     = $server
                        Database        = "master"
                        EnableException = $true
                    }
                    $masterasym = New-DbaDbAsymmetricKey @params
                }
            }

            # Create a database master key in the target database
            $null = $server.Databases["master"].Refresh()
            $dbmasterkey = $db | Get-DbaDbMasterKey

            if (-not $dbmasterkey) {
                $params = @{
                    SqlInstance     = $server
                    Database        = $db.Name
                    SecurePassword  = $MasterKeySecurePassword
                    EnableException = $true
                }
                $dbmasterkey = New-DbaDbMasterKey @params

                # Back up master key
                $params = @{
                    SqlInstance     = $server
                    Database        = $db.Name
                    Path            = $BakupPath
                    EnableException = $true
                    SecurePassword  = $MasterKeySecurePassword
                }
                $null = Backup-DbaDbMasterKey @params
            }

            # Create a database certificate or asymmetric key in the target database
            if ($EncryptorType -eq "Certificate") {
                $dbmastercert = Get-DbaDbCertificate -SqlInstance $server -Database $db.Name | Where-Object Name -notmatch "##"

                if ($dbmastercert.Count -gt 1) {
                    # Stop-Function
                }

                if (-not $dbmastercert) {
                    $params = @{
                        SqlInstance                  = $server
                        Database                     = $db.Name
                        StartDate                    = $CertificateStartDate
                        Subject                      = $CertificateSubject
                        ExpirationDate               = $CertificateExpirationDate
                        ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                        SecurePassword               = $CertificateSecurePassword
                        EnableException              = $true
                    }
                    $mastercert = New-DbaDbCertificate @params
                }
            } else {
                $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $server -Database $db.Name

                if (-not $masterasym) {
                    $params = @{
                        SqlInstance     = $server
                        Database        = $db.Name
                        EnableException = $true
                    }
                    $masterasym = New-DbaDbAsymmetricKey @params
                }
            }

            $null = $server.Databases[$db.Name].Refresh()
            # Create a database encryption key in the target database
            # Enable database encryption on the target database

            if ($db.HasDatabaseEncryptionKey) {
                Write-Message -Level Verbose -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key"
            } else {
                $null = $db | New-DbaDbEncryptionKey -Force:$force -EnableException
            }

            $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
        }
    }
}