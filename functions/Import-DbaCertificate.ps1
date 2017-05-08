Function Import-DbaCertificate
{
<#
.SYNOPSIS
Imports certificates from .cer files using smo.

.DESCRIPTION
Imports certificates from.cer files using smo.

.PARAMETER SqlServer
The SQL Server to create the certificates on.

.PARAMETER Path
The Path the contains the certificate and private key files.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Certificates
Imports just the certificates specified.

.PARAMETER Password
Secure string used to decrypt the private key.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
Original Author: Jess Pomfret (@jpomfret)
Tags: Migration, Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Import-DbaCertificate -SqlServer Server1 -Path \\Server1\Certificates -password (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
Imports all the certificates in the specified path.

.EXAMPLE
Import-DbaCertificate -SqlServer Server1 -Path \\Server1\Certificates -Certificates "CertTDE"
Prompts for password then imports certificate in the specified path named 'CertTDE'

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance","SqlInstance")]
        [object]$SqlServer,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Path,
        [System.Management.Automation.PSCredential]$SqlCredential,
		[Array]$Certificates,
		[Security.SecureString] $Password = (Read-Host "Password" -AsSecureString),
		[switch]$Silent	
	)

	BEGIN {
		$server = Connect-SqlServer $SqlServer $SqlCredential
	}
	
	PROCESS {
        if (!$path.StartsWith('\')) {
            Stop-Function -Message "Path should be a UNC share." -Continue
        }

        $Path = $Path.TrimEnd('\')

        if(!$Certificates) {
            $Certificates =  Get-ChildItem \\svtsqlrestore\BackupTest\cert *.cer | Select-Object -Expand Basename
        }

        foreach($Certificate in $Certificates) {

            if ($Pscmdlet.ShouldProcess("[$certificate]' on $SqlServer", "Importing Certificate")) {
                $Cert = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Certificate
                $Cert.name = $Certificate
                $Cert.parent = $Server.Databases['Master']
                Write-Message -Level Verbose -Message ("Creating Certificate: {0}" -f $Certificate)
                try {
                    $Cert.Create("$Path\$Certificate.cer", 1, "$Path\$Certificate.pvk", [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
                } catch {
                    Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                }
            }
        }    

    }
    END {
		$server.ConnectionContext.Disconnect()

	}

}