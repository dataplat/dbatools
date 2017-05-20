Function Import-DbaCertificate {
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
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Password
Secure string used to decrypt the private key.

.PARAMETER Database
The database where the certificate imports into. Defaults to master.
	
.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Original Author: Jess Pomfret (@jpomfret)
Tags: Migration, Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Import-DbaCertificate -SqlInstance Server1 -Path \\Server1\Certificates -password (ConvertTo-SecureString -force -AsPlainText GoodPass1234!!)
Imports all the certificates in the specified path.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Path,
		[string]$Database = "master",
		[Security.SecureString]$Password = (Read-Host "Password" -AsSecureString),
		[switch]$Silent
	)
	
	begin {
		
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
					$smocert.Create($fullcertname, 1, $privatekey, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
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
			
			if (![dbavalidate]::IsLocalhost($SqlInstance) -and !$fullname.StartsWith('\')) {
				Stop-Function -Message "Path ($fullname) must be a UNC share when SQL instance is not local." -Continue -Target $fullname
			}
			
			if (!(Test-DbaSqlPath -SqlInstance $server -Path $fullname)) {
				Stop-Function -Message "$SqlInstance cannot access $fullname" -Continue -Target $fullname
			}
			
			$item = Get-Item $fullname
			
			if ($item -is [System.IO.DirectoryInfo]) {
				foreach ($cert in (Get-ChildItem $fullname\* -Include *.crt, *.cer)) {
					new-smocert -directory $fullname -certname $cert.BaseName
				}
			}
			else {
				$directory = Split-Path $fullname
				new-smocert -directory $directory -certname $item.BaseName
			}
		}
	}
}