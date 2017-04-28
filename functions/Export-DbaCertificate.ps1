Function Export-DbaCertificate
{
<#
.SYNOPSIS
 Exports

.DESCRIPTION
Exports 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Path
The Path to the SQL File

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.EXAMPLE


.OUTPUTS
File to disk, and string path.

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[string]$Path,
		[array]$Databases,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	BEGIN
	{
		$server = Connect-SqlServer $SqlServer $SqlCredential
		
		#if ($server.versionMajor -lt 9) { "Windows 2000 not supported for sp_configure export."; break }
		
		if ($path.length -eq 0)
		{
			$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
			$mydocs = [Environment]::GetFolderPath('MyDocuments')
			$path = "$mydocs\$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
		}
	
	}
	
	PROCESS
		{

			# if the database is specified get the specific cert name
			if($Databases) {
				$certificates = @()
				foreach ($database in $Databases) {
					$certName = $server.Databases[$Database].DatabaseEncryptionKey.EncryptorName
					$certificates += $server.Databases['master'].Certificates | where-object {$_.name -eq $certName}
				}
			}
			else {
				$certificates = $server.Databases['master'].Certificates | where-object {$_.name -notlike '##*'}
			}

#specify cert name?
#password generator 
	#- I'd always prompt the user to enter it - you can do it with Read-Host and -UseSecureString or something
	#- or allow them to pass a credential
#ekm provider

			#Write-Message -Level Verbose -Message "Exporting Certificates"
			Write-host "Exporting Certificates"
			$pwd = Read-Host "Password:" #-AsSecureString
			write-host $pwd
			
			$certSql = @()
			foreach ($cert in $certificates) {
				#Write-Message -Level Verbose -Message ("Exporting Certificate: {0}" -f $cert.name )
				Write-Host ("Exporting Certificate: {0}" -f $cert.name )
				$exportLocation = "$path\$($cert.name)"
				Write-Host $exportLocation
				$cert.export("$exportLocation.cer","$exportLocation.pvk",$pwd)

				# Generate script
				$certSql += (
				"CREATE CERTIFICATE [{0}]  
				FROM FILE = '{1}{2}.cer'
				WITH PRIVATE KEY 
				( 
					FILE = '{1}{2}.pvk' ,
					DECRYPTION BY PASSWORD = '{3}'
				)
				GO
				" -f $cert.name, $exportLocation, $c.encryptorName ,$pwd)
			}
			try {
				$certsql | Out-File "$path\CreateCertificates.sql"
			}
			catch {
				throw "Can't write to $path"
			}
		#return $path
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
		
		#If ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
		#{
		#	Write-Output "Server configuration export finished"
		#}
	}
}