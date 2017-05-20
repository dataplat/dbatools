Function New-DbaCertificate {
<#
.SYNOPSIS
Creates a new database certificate

.DESCRIPTION
Creates a new database certificate. If no database is specified, the certificate will be created in master.

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the certificate will be created. Defaults to master.

.PARAMETER Name
Optional secure string used to create the certificate.

.PARAMETER Subject
Optional secure string used to create the certificate.
	
.PARAMETER StartDate
Optional secure string used to create the certificate.
	
.PARAMETER ExpirationDate
Optional secure string used to create the certificate.
	
.PARAMETER ActiveForServiceBrokerDialog
Optional secure string used to create the certificate.

.PARAMETER Password
Optional password - if no password is supplied, the password will be protected by the master key
	
.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
New-DbaCertificate -SqlInstance Server1

You will be prompted to securely enter your password, then a certificate will be created in the master database on server1 if it does not exist.

.EXAMPLE
New-DbaCertificate -SqlInstance Server1 -Database db1 -Confirm:$false

Supresses all prompts to install but prompts to securely enter your password and creates a certificate in the 'db1' database

.EXAMPLE
New-DbaCertificate -SqlInstance Server1 -WhatIf

Shows what would happen if the command were executed against server1

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory)]
		[string[]]$Name,
		[string[]]$Database = "master",
		[string[]]$Subject = $Name,
		[datetime]$StartDate = (Get-Date),
		[datetime]$ExpirationDate = $StartDate.AddYears(5),
		[switch]$ActiveForServiceBrokerDialog,
		[Security.SecureString]$Password = (Read-Host "Password (not required)" -AsSecureString),
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Target $instance -InnerErrorRecord $_ -Continue
			}
			
			foreach ($db in $database) {
				
				$smodb = $server.Databases[$db]
				
				if ($null -eq $smodb) {
					Stop-Function -Message "Database '$db' does not exist on $instance" -Target $server -Continue
				}
				
				foreach ($cert in $name) {
					if ($null -ne $smodb.Certificates[$cert]) {
						Stop-Function -Message "Certificate '$cert' already exists in the $db database on $instance" -Target $smodb -Continue
					}
					
					if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating certificate for database '$db' on $instance")) {
						try {
							$smocert = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Certificate $smodb, $cert
							
							$smocert.StartDate = $StartDate
							$smocert.Subject = $Subject
							$smocert.ExpirationDate = $ExpirationDate
							$smocert.ActiveForServiceBrokerDialog = $ActiveForServiceBrokerDialog
							
							if ($password.Length -gt 0) {
								$smocert.Create(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password))))
							}
							else {
								$smocert.Create()
							}
							
							Add-Member -InputObject $smocert -MemberType NoteProperty -Name ComputerName -value $server.NetName
							Add-Member -InputObject $smocert -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
							Add-Member -InputObject $smocert -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
							Add-Member -InputObject $smocert -MemberType NoteProperty -Name Database -value $smodb.Name
							
							Select-DefaultView -InputObject $smocert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
						}
						catch {
							if ($_.Exception.InnerException) {
								$exception = $_.Exception.InnerException.ToString() -Split "System.Data.SqlClient.SqlException: "
								$exception = ($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
							}
							else {
								$exception = $_.Exception
							}
							
							Stop-Function -Message "Failed to create certificate in $db on $instance. Exception: $exception" -Target $smocert -InnerErrorRecord $_ -Continue
						}
					}
				}
			}
		}
	}
}