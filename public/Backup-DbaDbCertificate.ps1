function Backup-DbaDbCertificate {
    <#
    .SYNOPSIS
        Exports database certificates and private keys to physical backup files on SQL Server instances.

    .DESCRIPTION
        Backs up database certificates by exporting them to .cer (certificate) and .pvk (private key) files on the SQL Server file system. This is essential for disaster recovery scenarios where you need to restore encrypted databases or migrate certificates to another instance. Without backing up certificates, you cannot decrypt TDE-enabled databases or access data encrypted with certificate-based encryption. Files are saved to the instance's default backup directory unless a custom path is specified.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Certificate
        Exports certificate that matches the name(s).

    .PARAMETER Database
        Exports the encryptor for specific database(s).

    .PARAMETER ExcludeDatabase
        Database(s) to skip when exporting encryptors.

    .PARAMETER EncryptionPassword
        A string value that specifies the secure password to encrypt the private key.

    .PARAMETER DecryptionPassword
        Secure string used to decrypt the private key.

    .PARAMETER Path
        The path to output the files to. The path is relative to the SQL Server itself. If no path is specified, the default data directory will be used.

    .PARAMETER Suffix
        The suffix of the filename of the exported certificate.

    .PARAMETER FileBaseName
        Override the default naming convention with a fixed name for the certificate and private key file name, useful when exporting a single certificate.
        ".cer" will be appended to the certificate file name and ".pvk" will be appended to the private key file name.

    .PARAMETER InputObject
        Enables piping from Get-DbaDbCertificate

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .NOTES
        Tags: CertBackup, Certificate, Backup
        Author: Jess Pomfret (@jpomfret)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaDbCertificate

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1

        Exports all the certificates on the specified SQL Server to the default data path for the instance.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -SqlCredential $cred

        Connects using sqladmin credential and exports all the certificates on the specified SQL Server to the default data path for the instance.

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -Certificate Certificate1

        Exports only the certificate named Certificate1 on the specified SQL Server to the default data path for the instance.

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -Database AdventureWorks

        Exports only the certificates for AdventureWorks on the specified SQL Server to the default data path for the instance.

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -ExcludeDatabase AdventureWorks

        Exports all certificates except those for AdventureWorks on the specified SQL Server to the default data path for the instance.

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates -EncryptionPassword (Get-Credential NoUsernameNeeded).Password

        Exports all the certificates and private keys on the specified SQL Server.

    .EXAMPLE
        PS C:\> $EncryptionPassword = (Get-Credential NoUsernameNeeded).Password
        PS C:\> $DecryptionPassword = (Get-Credential NoUsernameNeeded).Password
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -EncryptionPassword $EncryptionPassword -DecryptionPassword $DecryptionPassword

        Exports all the certificates on the specified SQL Server using the supplied DecryptionPassword, since an EncryptionPassword is specified private keys are also exported.

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates

        Exports all certificates on the specified SQL Server to the specified path.

    .EXAMPLE
        PS C:\> Backup-DbaDbCertificate -SqlInstance Server1 -Suffix DbaTools

        Exports all certificates on the specified SQL Server to the specified path, appends DbaTools to the end of the filenames.

    .EXAMPLE
        PS C:\> Get-DbaDbCertificate -SqlInstance sql2016 | Backup-DbaDbCertificate

        Exports all certificates found on sql2016 to the default data directory.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ParameterSetName = "instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ParameterSetName = "instance")]
        [object[]]$Certificate,
        [parameter(ParameterSetName = "instance")]
        [object[]]$Database,
        [parameter(ParameterSetName = "instance")]
        [object[]]$ExcludeDatabase,
        [Security.SecureString]$EncryptionPassword,
        [Security.SecureString]$DecryptionPassword,
        [System.IO.FileInfo]$Path,
        [string]$Suffix,
        [string]$FileBaseName,
        [parameter(ValueFromPipeline, ParameterSetName = "collection")]
        [Microsoft.SqlServer.Management.Smo.Certificate[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if (-not $EncryptionPassword -and $DecryptionPassword) {
            Stop-Function -Message "If you specify a decryption password, you must also specify an encryption password" -Target $DecryptionPassword
        }

        function export-cert ($cert) {
            $certName = $cert.Name
            $db = $cert.Parent
            $dbname = $db.Name
            $server = $db.Parent
            $instance = $server.Name

            if (-not $Path) {
                $Path = $server.BackupDirectory
            }

            if (-not $Path) {
                Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue
            }

            $actualPath = "$Path".TrimEnd('\').TrimEnd('/')

            if (-not (Test-DbaPath -SqlInstance $server -Path $actualPath)) {
                Stop-Function -Message "$SqlInstance cannot access $actualPath" -Target $actualPath
            }

            $fileinstance = $instance.ToString().Replace('\', '$')
            $targetBaseName = "$fileinstance-$dbname-$certName$Suffix"
            if ($FileBaseName) {
                $targetBaseName = $FileBaseName
            }
            $fullCertName = Join-DbaPath -SqlInstance $server -Path $actualPath -ChildPath $targetBaseName

            # if the base file name exists, then default to old style of appending a timestamp
            if (Test-DbaPath -SqlInstance $server -Path "$fullCertName.cer") {
                if ($Suffix) {
                    Stop-Function -Message "$fullCertName.cer already exists on $($server.Name)" -Target $actualPath -Continue
                } else {
                    $time = Get-Date -Format yyyyMMddHHmmss
                    $fullCertName = "$fullCertName-$time"
                    # Sleep for a second to avoid another export in the same second
                    Start-Sleep -Seconds 1
                }
            }

            $exportPathKey = "$fullCertName.pvk"

            if ($Pscmdlet.ShouldProcess($instance, "Exporting certificate $certName from $db on $instance to $actualPath")) {
                Write-Message -Level Verbose -Message "Exporting Certificate: $certName to $fullCertName"
                try {
                    $exportPathCert = "$fullCertName.cer"

                    # because the password shouldn't go to memory...
                    if ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -gt 0) {

                        Write-Message -Level Verbose -Message "Both passwords passed in. Will export both cer and pvk."

                        $cert.export(
                            $exportPathCert,
                            $exportPathKey,
                            ($EncryptionPassword | ConvertFrom-SecurePass),
                            ($DecryptionPassword | ConvertFrom-SecurePass)
                        )
                    } elseif ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -eq 0) {
                        Write-Message -Level Verbose -Message "Only encryption password passed in. Will export both cer and pvk."

                        $cert.export(
                            $exportPathCert,
                            $exportPathKey,
                            ($EncryptionPassword | ConvertFrom-SecurePass)
                        )
                    } else {
                        Write-Message -Level Verbose -Message "No passwords passed in. Will export just cer."
                        $exportPathKey = "Password required to export key"
                        $cert.export($exportPathCert)
                    }

                    [PSCustomObject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Database       = $db.Name
                        DatabaseID     = $db.ID
                        Certificate    = $certName
                        Path           = $exportPathCert
                        Key            = $exportPathKey
                        ExportPath     = $exportPathCert
                        ExportKey      = $exportPathKey
                        exportPathCert = $exportPathCert
                        exportPathKey  = $exportPathKey
                        Status         = "Success"
                    } | Select-DefaultView -ExcludeProperty exportPathCert, exportPathKey, ExportPath, ExportKey
                } catch {
                    if ($_.Exception.InnerException) {
                        $exception = $_.Exception.InnerException.ToString() -Split "Microsoft.Data.SqlClient.SqlException: "
                        $exception = ($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
                    } else {
                        $exception = $_.Exception
                    }
                    Stop-Function -Message "$certName from $db on $instance cannot be exported." -Continue -Target $cert -ErrorRecord $PSItem
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDbCertificate -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Certificate $Certificate
        }

        if ($Certificate) {
            $missingCerts = $Certificate | Where-Object { $InputObject.Name -notcontains $_ }

            if ($missingCerts) {
                Write-Message -Level Warning -Message "Database certificate(s) $missingCerts not found in Database(s)=$Database on Instance(s)=$SqlInstance"
            }
        }

        foreach ($cert in $InputObject) {
            if ($cert.Name.StartsWith("##")) {
                Write-Message -Level Verbose -Message "Skipping system cert $cert"
            } else {
                export-cert $cert
            }
        }
    }
}