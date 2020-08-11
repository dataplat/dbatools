function Backup-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Backs up a computer certificate - useful for older systems and backing up remote certs to local disk.

    .DESCRIPTION
        Backs up a computer certificate - useful for older systems and backing up remote certs to local disk.

    .PARAMETER InputObject
        The target certificate object. Accepts input from Get-DbaComputerCertificate.

    .PARAMETER Path
        Export to a directory

    .PARAMETER FilePath
        Export to a specific file name

    .PARAMETER Type
        Export type. Options include: Authenticode, Cert, Pfx, Pkcs12, Pkcs7, SerializedCert.

    .PARAMETER SecurePassword
        Export using a password

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaComputerCertificate

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