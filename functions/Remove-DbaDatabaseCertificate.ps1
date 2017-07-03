function Remove-DbaDatabaseCertificate {
<#
.SYNOPSIS
Deletes specified database certificate

.DESCRIPTION
Deletes specified database certificate

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the certificate will be removed.

.PARAMETER Certificate
The certificate that will be removed

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.PARAMETER CertificateCollection 
Internal parameter to support pipeline input

.NOTES
Tags: Certificate
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Remove-DbaDatabaseCertificate -SqlInstance Server1

The certificate in the master database on server1 will be removed if it exists.

.EXAMPLE
Remove-DbaDatabaseCertificate -SqlInstance Server1 -Database db1 -Confirm:$false

Suppresses all prompts to remove the certificate in the 'db1' database and drops the key.


#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[parameter(Mandatory, ParameterSetName = "instance")]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory, ParameterSetName = "instance")]
		[object[]]$Database,
		[parameter(Mandatory, ParameterSetName = "instance")]
		[object[]]$Certificate,
		[parameter(ValueFromPipeline, ParameterSetName = "collection")]
		[Microsoft.SqlServer.Management.Smo.Certificate[]]$CertificateCollection,
		[switch]$Silent
	)
	begin {
		
		function drop-cert ($smocert) {
			$server = $smocert.Parent.Parent
			$instance = $server.DomainInstanceName
			$cert = $smocert.Name
			$db = $smocert.Parent.Name
			
			if ($Pscmdlet.ShouldProcess($instance, "Dropping the certificate named $cert for database '$db' on $instance")) {
				try {
					$smocert.Drop()
					Write-Message -Level Verbose -Message "Successfully removed certificate named $cert from the $db database on $instance"
					
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $instance
						Database = $db
						Certificate = $cert
						Status = "Success"
					}
				}
				catch {
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $instance
						Database = $db
						Certificate = $cert
						Status = "Failure"
					}
					Stop-Function -Message "Failed to drop certificate named $cert from $db on $instance." -Target $smocert -InnerErrorRecord $_ -Continue
				}
			}
		}
	}
	process {
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			foreach ($db in $Database) {
				$smodb = $server.Databases[$db]
				
				if ($null -eq $smodb) {
					Stop-Function -Message "Database '$db' does not exist on $instance" -Target $smodb -Continue
				}
				
				foreach ($cert in $certificate) {
					$smocert = $smodb.Certificates[$cert]
					
					if ($null -eq $smocert) {
						Stop-Function -Message "No certificate named $cert exists in the $db database on $instance" -Target $smodb.Certificates -Continue
					}
					
					Drop-Cert -smocert $smocert
				}
			}
		}
		
		foreach ($smocert in $CertificateCollection) {
			Drop-Cert -smocert $smocert
		}
	}
}