Function Remove-DbaMasterKey {
<#
.SYNOPSIS
Deletes specified database master key

.DESCRIPTION
Deletes specified database master key. If no database is specified, the master key will be deleted from master.

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the master key will be removed. Defaults to master.

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
Remove-DbaMasterKey -SqlInstance Server1

You will be prompted to securely enter your password, then a master key will be created in the master database on server1 if it does not exist.

.EXAMPLE
Remove-DbaMasterKey -SqlInstance Server1 -Database db1 -Confirm:$false

Supresses all prompts to install but prompts to securely enter your password and creates a master key in the 'db1' database

.EXAMPLE
Remove-DbaMasterKey -SqlInstance Server1 -WhatIf

Shows what would happen if the command were executed against server1

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string[]]$Database = "master",
		[switch]$Silent
	)
	
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
				$smodb = $server.Databases[$database]
				if ($null -eq $smodb.MasterKey) {
					Stop-Function -Message "No master key exists in the $db database on $instance" -Target $smodb -Continue
				}
				
				if ($Pscmdlet.ShouldProcess($SqlInstance, "Dropping the master key for database '$db' on $instance")) {
					try {
						$masterkey = New-Object Microsoft.SqlServer.Management.Smo.MasterKey $smodb
						$masterkey.Drop()
					}
					catch {
						Stop-Function -Message "Failed to drop master key from $db on $instance" -Target $masterkey -InnerErrorRecord $_ -Continue
					}
				}
			}
		}
	}
}