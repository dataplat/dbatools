Function New-DbaMasterKey {
<#
.SYNOPSIS
Creates a new database master key

.DESCRIPTION
Creates a new database master key. If no database is specified, the master key will be created in master.

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the master key will be created. Defaults to master.

.PARAMETER Password
Secure string used to create the key.

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
New-DbaMasterKey -SqlInstance Server1

You will be prompted to securely enter your password, then a master key will be created on server1 if it does not exist.

.EXAMPLE
New-DbaMasterKey -SqlInstance Server1 -WhatIf

Shows what would happen if the command were executed against server1

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string[]]$Database = "master",
		[parameter(Mandatory)]
		[Security.SecureString]$Password = (Read-Host "Password" -AsSecureString),
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
				if ($null -ne $smodb.MasterKey) {
					Stop-Function -Message "Master key already exists in the $db on $instance" -Target $smodb.MasterKey -Continue
				}
				
				if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating master key for $db on $instance")) {
					try {
						$masterkey = New-Object Microsoft.SqlServer.Management.Smo.MasterKey $smodb
						$masterkey.Create($Password)
					}
					catch {
						Stop-Function -Message "Failed to create master key in $db on $instance" -Target $masterkey -InnerErrorRecord $_ -Continue
					}
				}
			}
		}
	}
}