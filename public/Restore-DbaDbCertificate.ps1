function Restore-DbaDbCertificate {
    <#
    .SYNOPSIS
        Restores database certificates from .cer and .pvk files into SQL Server databases.

    .DESCRIPTION
        Restores database certificates and their associated private keys from backup files into SQL Server databases. This function is essential for recovering certificates used in TDE (Transparent Data Encryption), backup encryption, Always Encrypted, and other SQL Server security features after database migrations, disaster recovery, or server rebuilds.

        The function automatically locates matching private key files (.pvk) for each certificate (.cer) when processing directories, or you can specify key file paths explicitly. Handles password-protected private keys with secure credential management, and allows you to re-encrypt keys during the restore process if needed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the file system path to certificate files (.cer) or a directory containing multiple certificates. When pointing to a directory, the function processes all .cer files found within it.
        Use this to restore certificates from your certificate backup location after disaster recovery or server migrations.

    .PARAMETER KeyFilePath
        Specifies the path to the private key file (.pvk) associated with the certificate. If not provided, the function automatically searches for a matching .pvk file in the same directory as the certificate.
        Only specify this when your private key files are stored in a different location from your certificate files.

    .PARAMETER DecryptionPassword
        Provides the password required to decrypt the private key file (.pvk) during certificate restoration. This password was set when the certificate was originally backed up.
        Required for all certificate restores since private keys are encrypted by default when exported from SQL Server.

    .PARAMETER EncryptionPassword
        Sets a new password to encrypt the private key after restoration to SQL Server. If not specified, the restored certificate will be encrypted with the database master key.
        Use this when you want to change the private key encryption method or set a specific password for the restored certificate.

    .PARAMETER Database
        Specifies the target database where the certificate will be restored. Defaults to the master database if not specified.
        Use this when restoring certificates for specific database features like TDE, Always Encrypted, or application-specific encryption within user databases.

    .PARAMETER Name
        Specifies a custom name for the restored certificate in SQL Server. If not provided, the function derives the name from the certificate file name, removing instance and database prefixes.
        Use this when you need the certificate to have a specific name that differs from the backup file naming convention.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CertBackup, Certificate, Backup
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-DbaDbCertificate

    .EXAMPLE
        PS C:\> $securepass = Get-Credential usernamedoesntmatter | Select-Object -ExpandProperty Password
        PS C:\> Restore-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates -DecryptionPassword $securepass

        Restores all the certificates in the specified path, password is used to both decrypt and encrypt the private key.

    .EXAMPLE
        PS C:\> Restore-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates\DatabaseTDE.cer -DecryptionPassword (Get-Credential usernamedoesntmatter).Password

        Restores the DatabaseTDE certificate to Server1 and uses the MasterKey to encrypt the private key.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("FullName", "ExportPath")]
        [string[]]$Path,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("Key")]
        [string[]]$KeyFilePath,
        [Security.SecureString]$EncryptionPassword,
        [string]$Database = "master",
        [string]$Name,
        [Alias("Password", "SecurePassword")]
        [Security.SecureString]$DecryptionPassword = (Read-Host "Decryption password" -AsSecureString),
        [switch]$EnableException
    )
    process {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        foreach ($dir in $Path) {
            if (-not (Test-DbaPath -SqlInstance $server -Path $dir)) {
                Stop-Function -Message "$SqlInstance cannot access $dir" -Continue -Target $dir
            }

            try {
                $isdir = ($server.Query("EXEC master.dbo.xp_fileexist '$dir'")).Item(1)
            } catch {
                Stop-Function -Message $_ -ErrorRecord $_ -Target $server.Name -Continue
            }
            if ($isdir) {
                Write-Message -Level Verbose -Message "Path is a directory - processing all certs within"
                $path = (Get-DbaFile -SqlInstance $server -Path $dir -FileType cer).Filename
            }

            foreach ($fullname in $path) {
                Write-Message -Level Verbose -Message ("Processing {0}" -f $fullname)

                $directory = Split-Path $fullname
                $filename = Split-Path $fullname -Leaf
                $certname = [io.path]::GetFileNameWithoutExtension($filename)
                $fullcertname = Join-DbaPath -SqlInstance $server -Path $directory -ChildPath "$certname.cer"

                if (-not $KeyFilePath) {
                    $privatekey = Join-DbaPath -SqlInstance $server -Path $directory -ChildPath "$certname.pvk"
                } else {
                    $privatekey = $KeyFilePath
                }

                $instance = $server.Name
                $fileinstance = $instance.ToString().Replace('\', '$')
                $certname = $certname.Replace("$fileinstance-$Database-", "")
                if ($certname -match "-$Database-") {
                    $tempcertname = $certname -split "-" | Select-Object -First 1 -Skip 2
                    if ($tempcertname) {
                        $certname = $tempcertname
                    }
                }

                if ($certname -match '([0-9]{4})(0[1-9]|1[0-2])(0[1-9]|[1-2][0-9]|3[0-1])(2[0-3]|[01][0-9])([0-5][0-9])([0-5][0-9])') {
                    $certname = $certname.Replace($matches[0], "")
                }
                $certname = $certname.TrimEnd("-")
                if ($PSBoundParameters.Name) {
                    $certificatename = $Name
                } else {
                    $certificatename = $certname
                }

                if ($Pscmdlet.ShouldProcess("$certificatename on $SqlInstance", "Importing certificate to $Database")) {
                    $smocert = New-Object Microsoft.SqlServer.Management.Smo.Certificate
                    $smocert.Name = $certificatename
                    $smocert.Parent = $server.Databases[$Database]
                    Write-Message -Level Verbose -Message "Creating Certificate: $certificatename"
                    Write-Message -Level Verbose -Message "Full certificate path: $fullcertname"
                    Write-Message -Level Verbose -Message "Private key: $privatekey"
                    try {
                        if ($EncryptionPassword) {
                            $smocert.Create($fullcertname, 1, $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass), ($EncryptionPassword | ConvertFrom-SecurePass))
                        } else {
                            $smocert.Create($fullcertname, 1, $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass))
                        }
                    } catch {
                        try {
                            if ($EncryptionPassword) {
                                $smocert.Create($fullcertname, $([Microsoft.SqlServer.Management.Smo.CertificateSourceType]::"File"), $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass), ($EncryptionPassword | ConvertFrom-SecurePass))
                            } else {
                                $smocert.Create($fullcertname, $([Microsoft.SqlServer.Management.Smo.CertificateSourceType]::"File"), $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass))
                            }
                        } catch {
                            Stop-Function -Message $_ -ErrorRecord $_ -Target $instance -Continue
                        }
                    }
                    Get-DbaDbCertificate -SqlInstance $server -Database $Database -Certificate $smocert.Name
                }
            }
        }
    }
}