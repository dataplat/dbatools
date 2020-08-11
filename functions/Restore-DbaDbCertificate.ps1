function Restore-DbaDbCertificate {
    <#
    .SYNOPSIS
        Imports certificates from .cer files using SMO.

    .DESCRIPTION
        Imports certificates from.cer files using SMO.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        The Path the contains the certificate and private key files. The path can be a directory or a specific certificate.

    .PARAMETER DecryptionPassword
        Secure string used to decrypt the private key.

    .PARAMETER EncryptionPassword
        If specified this will be used to encrypt the private key.

    .PARAMETER Database
        The database where the certificate imports into. Defaults to master.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Certificate
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
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("FullName")]
        [object[]]$Path,
        [Security.SecureString]$EncryptionPassword,
        [string]$Database = "master",
        [Alias("Password", "SecurePassword")]
        [Security.SecureString]$DecryptionPassword = (Read-Host "Password" -AsSecureString),
        [switch]$EnableException
    )
    process {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failed to connect to: $SqlInstance" -Target $SqlInstance -ErrorRecord $_
            return
        }

        foreach ($dir in $Path) {
            if (-not $SqlInstance.IsLocalHost -and -not $dir.StartsWith('\')) {
                Stop-Function -Message "Path ($dir) must be a UNC share when SQL instance is not local." -Continue -Target $fullname
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $dir)) {
                Stop-Function -Message "$SqlInstance cannot access $dir" -Continue -Target $dir
            }

            if (Test-Path $dir -PathType Container) {
                Write-Message -Level Verbose -Message "Path is a directory - processing all cer's within"
                $path = Get-ChildItem $dir "*.cer" | Select-Object -expand FullName
            }

            foreach ($fullname in $path) {
                Write-Message -Level Verbose -Message ("Processing {0}" -f $fullname)

                $directory = Split-Path $fullname
                $filename = Split-Path $fullname -Leaf
                $certname = [io.path]::GetFileNameWithoutExtension($filename)

                if ($Pscmdlet.ShouldProcess("$certname on $SqlInstance", "Importing Certificate")) {
                    $smocert = New-Object Microsoft.SqlServer.Management.Smo.Certificate
                    $smocert.Name = $certname
                    $smocert.Parent = $server.Databases[$Database]
                    Write-Message -Level Verbose -Message "Creating Certificate: $certname"
                    $fullcertname = "$directory\$certname.cer"
                    $privatekey = "$directory\$certname.pvk"
                    Write-Message -Level Verbose -Message "Full certificate path: $fullcertname"
                    Write-Message -Level Verbose -Message "Private key: $privatekey"
                    try {
                        if ($EncryptionPassword) {
                            $smocert.Create($fullcertname, 1, $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword)), [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword)))
                        } else {
                            $smocert.Create($fullcertname, 1, $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword)))
                        }
                    } catch {
                        try {
                            if ($EncryptionPassword) {
                                $smocert.Create($fullcertname, $([Microsoft.SqlServer.Management.Smo.CertificateSourceType]::"File"), $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword)), [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($EncryptionPassword)))
                            } else {
                                $smocert.Create($fullcertname, $([Microsoft.SqlServer.Management.Smo.CertificateSourceType]::"File"), $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($DecryptionPassword)))
                            }
                        } catch {
                            Stop-Function -Message $_ -ErrorRecord $_ -Target $instance -Continue
                        }
                    }
                }
            }
            Get-DbaDbCertificate -SqlInstance $server -Database $Database -Certificate $smocert.Name
        }
    }
}