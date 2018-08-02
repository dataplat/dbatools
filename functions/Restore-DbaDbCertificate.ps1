function Restore-DbaDbCertificate {
    <#
.SYNOPSIS
Imports certificates from .cer files using SMO.

.DESCRIPTION
Imports certificates from.cer files using SMO.

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER Path
The Path the contains the certificate and private key files. The path can be a directory or a specific certificate.

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

.PARAMETER Password
Secure string used to decrypt the private key.

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
Author: Jess Pomfret (@jpomfret)

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
Restore-DbaDbCertificate -SqlInstance Server1 -Path \\Server1\Certificates -password (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
Imports all the certificates in the specified path.

#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Path,
        [object]$Database = "master",
        [Security.SecureString]$Password = (Read-Host "Password" -AsSecureString),
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Retore-DbaDatabaseCertificate

        function new-smocert ($directory, $certname) {
            if ($Pscmdlet.ShouldProcess("$cert on $SqlInstance", "Importing Certificate")) {
                $smocert = New-Object Microsoft.SqlServer.Management.Smo.Certificate
                $smocert.Name = $certname
                $smocert.Parent = $server.Databases[$Database]
                Write-Message -Level Verbose -Message "Creating Certificate: $certname"
                try {
                    $fullcertname = "$directory\$certname.cer"
                    $privatekey = "$directory\$certname.pvk"
                    Write-Message -Level Verbose -Message "Full certificate path: $fullcertname"
                    Write-Message -Level Verbose -Message "Private key: $privatekey"
                    $fromfile = 1
                    $smocert.Create($fullcertname, $fromfile, $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)), [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
                    $smocert
                }
                catch {
                    Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                }
            }
        }

        try {
            Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlcredential
        }
        catch {
            Stop-Function -Message "Failed to connect to: $SqlInstance" -Target $SqlInstance -InnerErrorRecord $_
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($fullname in $path) {

            if (-not $SqlInstance.IsLocalHost -and -not $fullname.StartsWith('\')) {
                Stop-Function -Message "Path ($fullname) must be a UNC share when SQL instance is not local." -Continue -Target $fullname
            }

            if (-not (Test-DbaSqlPath -SqlInstance $server -Path $fullname)) {
                Stop-Function -Message "$SqlInstance cannot access $fullname" -Continue -Target $fullname
            }

            $directory = Split-Path $fullname
            $filename = Split-Path $fullname -Leaf
            $basename = [io.path]::GetFileNameWithoutExtension($filename)
            $cert = new-smocert -directory $directory -certname $basename
            Get-DbaDbCertificate -SqlInstance $server -Database $Database -Certificate $cert.Name
        }
    }
}