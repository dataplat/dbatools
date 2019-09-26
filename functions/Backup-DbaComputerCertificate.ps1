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

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate | Backup-DbaComputerCertificate -Path C:\temp

        Backs up all certs to C:\temp. Autonames the files.

    .EXAMPLE
        PS C:\> Backup-DbaComputerCertificate -FilePath C:\temp\cert.cer

        Backs up the local C:\temp\cert.cer from the local computer's LocalMachine\My (Personal) certificate store.

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