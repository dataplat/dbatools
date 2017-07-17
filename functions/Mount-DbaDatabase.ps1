function Mount-DbaDatabase {
	<#
		.SYNOPSIS
			Attach a SQL Server Database

		.DESCRIPTION
			This command will attach a SQL Server database

		.PARAMETER SqlInstance
			The target SQL Server

		.PARAMETER SqlCredential
			PSCredential object to connect as. If not specified, current Windows login will be used

		.PARAMETER Database
			A string value that specifies the name of the database to be attached

		.PARAMETER FileStructure
			A StringCollection object value that contains a list database files
	
		.PARAMETER DatabaseOwner
			Returns list of SQL Server databases owned by the specified logins

		.PARAMETER AttachOption
			A AttachOptions object value that contains the attachment options. Valid options include 
			None, RebuildLog, EnableBroker, NewBroker and ErrorBrokerConversations
	
		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Database
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Mount-DbaDatabase

		.EXAMPLE
			Mount-DbaDatabase -SqlInstance localhost

			Incomplete example, hold on
	
	#>
	[CmdletBinding(SupportsShouldProcess)]
	Param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[parameter(Mandatory)]
		[string[]]$Database,
		[System.Collections.Specialized.StringCollection]$FileStructure,
		[string]$DatabaseOwner,
		[ValidateSet('None','RebuildLog','EnableBroker','NewBroker', 'ErrorBrokerConversations')]
		[string]$AttachOption = "None",
		[switch]$Silent
	)
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if (-not $server.Logins.Item($DatabaseOwner)) {
				try {
					$DatabaseOwner = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
				}
				catch {
					$DatabaseOwner = "sa"
				}
			}
			
			foreach ($db in $database) {
				if (-Not (Test-Bound -Parameter FileStructure)) {
					#$backuphistory = Get-DbaBackupHistory -SqlInstance $server -LastFull -Database $db
					$backuphistory = Get-DbaBackupHistory -SqlInstance sql2016 -Database DBWithCDC -Type Full | Sort-Object End -Descending | Select-Object -First 1

					if (-not $backuphistory) {
						$message = "Could not enumerate backup history to automatically build FileStructure. Rerun the command and provide the filestructure parameter"
						Stop-Function -Message $message -Target $db -Continue
					}
					
					$backupfile = $backuphistory.Path[0]
					$filepaths = (Read-DbaBackupHeader -SqlInstance $server -FileList -Path $backupfile).PhysicalName
					
					$FileStructure = New-Object System.Collections.Specialized.StringCollection
					foreach ($file in $filepaths) {
						$exists = Test-DbaSqlpath -SqlInstance $server -Path $file
						if (-not $exists) {
							$message = "Could not find the files to build the FileStructure. Rerun the command and provide the FileStructure parameter"
							Stop-Function -Message $message -Target $file -Continue
						}
						
						$null = $FileStructure.Add($file)
					}
				}
				
				If ($Pscmdlet.ShouldProcess($server, "Attaching $Database with $DatabaseOwner as database owner and $AttachOption as attachoption")) {
					try {
						$server.AttachDatabase($db, $FileStructure, $DatabaseOwner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::$AttachOption)
						
						[pscustomobject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database = $db
							AttachStatus = "Success"
							AttachOption = $AttachOption
							FileStructure = $FileStructure
						}
					}
					catch {
						Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server
					}
				}
			}
		}
	}
}