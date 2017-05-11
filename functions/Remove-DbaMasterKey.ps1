Function Remove-DbaMasterKey {
<#
.SYNOPSIS
Deletes specified database master key

.DESCRIPTION
Deletes specified database master key.

.PARAMETER SqlInstance
The target SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the master key will be removed.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.PARAMETER MasterKeyCollection
Internal parameter to support pipeline input

.NOTES
Tags: Certificate
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Remove-DbaMasterKey -SqlInstance Server1

The master key in the master database on server1 will be removed if it exists.

.EXAMPLE
Remove-DbaMasterKey -SqlInstance Server1 -Database db1 -Confirm:$false

Supresses all prompts to remove the master key in the 'db1' database and drops the key.

.EXAMPLE
Remove-DbaMasterKey -SqlInstance Server1 -WhatIf

Shows what would happen if the command were executed against server1

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[parameter(Mandatory, ParameterSetName = "instance")]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory, ParameterSetName = "instance")]
		[string[]]$Database,
		[parameter(ValueFromPipeline, ParameterSetName = "collection")]
		[Microsoft.SqlServer.Management.Smo.MasterKey[]]$MasterKeyCollection,
		[switch]$Silent
	)
	
	begin {
		function drop-masterkey ($masterkey) {
			if ($Pscmdlet.ShouldProcess($SqlInstance, "Dropping the master key for database '$db' on $instance")) {
				try {
					
					$server = $masterkey.Parent.Parent
					$instance = $server.DomainInstanceName
					$cert = $masterkey.Name
					$db = $masterkey.Parent.Name
					
					$masterkey.Drop()
					Write-Message -Level Verbose -Message "Successfully removed master key from the $db database on $instance"
					
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.name
						Status = "Success"
					}
				}
				catch {
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.name
						Status = "Failure"
					}
					Stop-Function -Message "Failed to drop master key from $db on $instance." -Target $db -InnerErrorRecord $_ -Continue
				}
			}
		}
	}
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Target $instance -InnerErrorRecord $_ -Continue
			}
			
			foreach ($db in $database) {
				$smodb = $server.Databases[$db]
				$masterkey = $smodb.MasterKey
				if ($null -eq $smodb) {
					Stop-Function -Message "Database '$db' does not exist on $instance" -Target $smodb -Continue
				}
				
				if ($null -eq $masterkey) {
					Stop-Function -Message "No master key exists in the $db database on $instance" -Target $smodb -Continue
				}
				
				Drop-Masterkey -masterkey $masterkey
			}
		}
		
		foreach ($masterkey in $MasterKeyCollection) {
			Drop-Masterkey -masterkey $masterkey
		}
	}
}
