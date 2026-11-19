function Backup-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Exports computer certificates to disk for SQL Server network encryption backup and disaster recovery.

    .DESCRIPTION
        Exports computer certificates from the local or remote certificate store to files on disk. This is essential for backing up certificates used for SQL Server network encryption before server migrations, certificate renewals, or disaster recovery scenarios. The function works with certificate objects from Get-DbaComputerCertificate and supports multiple export formats including standard .cer files and password-protected .pfx files for complete private key backup.

    .PARAMETER InputObject
        The certificate objects to export, typically from Get-DbaComputerCertificate pipeline output.
        Use this to specify which certificates to backup for SQL Server network encryption recovery scenarios.

    .PARAMETER Path
        Specifies the target directory where certificate files will be saved with auto-generated filenames.
        Files are named using the pattern: ComputerName-Thumbprint.cer for easy identification during recovery.

    .PARAMETER FilePath
        Specifies the exact file path and name for the exported certificate.
        Use this when you need to control the output filename or when backing up a single certificate to a specific location.

    .PARAMETER Type
        Determines the certificate export format for different backup and deployment scenarios.
        Use 'Cert' for public key only backups, 'Pfx' for complete certificate with private key backup, or other formats based on your security requirements.

    .PARAMETER SecurePassword
        Provides password protection for certificate exports, required when exporting private keys with Pfx format.
        Essential for securing certificate backups that contain private keys used for SQL Server TLS encryption.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CertBackup, Certificate, Backup
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaComputerCertificate

    .OUTPUTS
        System.IO.FileInfo

        Returns one FileInfo object per certificate that was successfully exported. This represents the certificate file created on disk.

        Properties:
        - Name: The filename of the exported certificate (e.g., ComputerName-Thumbprint.cer)
        - FullName: The complete path to the exported certificate file
        - DirectoryName: The directory where the certificate file is stored
        - Directory: The DirectoryInfo object of the parent directory
        - Extension: The file extension (.cer, .pfx, etc., based on Type parameter)
        - Length: The size of the exported certificate file in bytes
        - CreationTime: When the certificate file was created
        - LastWriteTime: When the certificate file was last written
        - Attributes: File attributes (Archive, Normal, etc.)

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate | Backup-DbaComputerCertificate -Path C:\temp

        Backs up all certs to C:\temp. Auto-names the files.

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 | Backup-DbaComputerCertificate -FilePath C:\temp\29C469578D6C6211076A09CEE5C5797EEA0C2713.cer

        Backs up certificate with the thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 to the temp directory.
    #>
    [CmdletBinding()]
    param (
        [Alias("Password")]
        [SecureString]$SecurePassword,
        [parameter(ValueFromPipeline, Mandatory)]
        [object[]]$InputObject,
        [string]$Path = $pwd,
        [string]$FilePath,
        [ValidateSet("Authenticode", "Cert", "Pfx", "Pkcs12", "Pkcs7", "SerializedCert")]
        [string]$Type = "Cert",
        [switch]$EnableException
    )
    process {
        foreach ($cert in $InputObject) {
            if ((Test-Bound -Parameter FilePath -Not)) {
                $FilePath = "$Path\$($cert.ComputerName)-$($cert.Thumbprint).cer"
            }
            $certfromraw = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert.RawData, $SecurePassword)
            [io.file]::WriteAllBytes($FilePath, $certfromraw.Export($Type))
            Get-ChildItem $FilePath
        }
    }
}