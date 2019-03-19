#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Restore-DbaDbCertificate {
    <#
    .SYNOPSIS
        Imports certificates from .cer files using SMO.

    .DESCRIPTION
        Imports certificates from.cer files using SMO.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        The Path the contains the certificate and private key files. The path can be a directory or a specific certificate.

    .PARAMETER SecurePassword
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
        PS C:\> Restore-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates -SecurePassword (ConvertTo-SecureString -Force -AsPlainText GoodPass1234!!)

        Restores all the certificates in the specified path, password is used to both decrypt and encrypt the private key.

    .EXAMPLE
        PS C:\> Restore-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates\DatabaseTDE.cer -SecurePassword (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)

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
        [Alias("Password")]
        [Security.SecureString]$SecurePassword = (Read-Host "Password" -AsSecureString),
        [switch]$EnableException
    )
    process {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlcredential
        } catch {
            Stop-Function -Message "Failed to connect to: $SqlInstance" -Target $SqlInstance -ErrorRecord $_
            return
        }

        foreach ($fullname in $Path) {
            if (-not $SqlInstance.IsLocalHost -and -not $fullname.StartsWith('\')) {
                Stop-Function -Message "Path ($fullname) must be a UNC share when SQL instance is not local." -Continue -Target $fullname
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $fullname)) {
                Stop-Function -Message "$SqlInstance cannot access $fullname" -Continue -Target $fullname
            }

            $directory = Split-Path $fullname
            $filename = Split-Path $fullname -Leaf
            $certname = [io.path]::GetFileNameWithoutExtension($filename)

            if ($Pscmdlet.ShouldProcess("$certname on $SqlInstance", "Importing Certificate")) {
                $smocert = New-Object Microsoft.SqlServer.Management.Smo.Certificate
                $smocert.Name = $certname
                $smocert.Parent = $server.Databases[$Database]
                Write-Message -Level Verbose -Message "Creating Certificate: $certname"
                try {
                    $fullcertname = "$directory\$certname.cer"
                    $privatekey = "$directory\$certname.pvk"
                    Write-Message -Level Verbose -Message "Full certificate path: $fullcertname"
                    Write-Message -Level Verbose -Message "Private key: $privatekey"
                    $fromfile = $true

                    if ($EncryptionPassword) {
                        $smocert.Create($fullcertname, $fromfile, $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)), [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
                    } else {
                        $smocert.Create($fullcertname, $fromfile, $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
                    }
                    $cert = $smocert
                } catch {
                    Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                }
            }
            Get-DbaDbCertificate -SqlInstance $server -Database $Database -Certificate $cert.Name
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Retore-DbaDatabaseCertificate

    }
}