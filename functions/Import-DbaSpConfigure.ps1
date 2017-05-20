Function Import-DbaSpConfigure
{
 <#
.SYNOPSIS
 Updates sp_configure settings on destination server.

.DESCRIPTION
Updates sp_configure settings on destination server.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER Path
The Path to the SQL File

.PARAMETER Force
Overrides Major Version Check

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.EXAMPLE
Import-DbaSpConfigure sqlserver sqlcluster $SourceSqlCredential $DestinationSqlCredential

Imports the spconfigure settings from the source server sqlserver and sets them on the sqlcluster server
using the SQL credentials stored in the variables

.EXAMPLE
Import-DbaSpConfigure -SqlInstance sqlserver -Path .\spconfig.sql -SqlCredential $SqlCredential

Imports the spconfigure settings from the file .\spconfig.sql and sets them on the sqlcluster server
using the SQL credential stored in the variables

.OUTPUTS
    $true if success
    $false if failure

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[object]$Source,
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlInstance,
		[string]$Path,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Force
		
	)
	BEGIN {
	
		if ($Path.length -eq 0)
		{
			$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
			$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
			
			$source = $sourceserver.DomainInstanceName
			$destination = $destserver.DomainInstanceName
		} else {
			$server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
			if ((Test-Path $Path) -eq $false) { throw "File Not Found" }
		}
	
	}
	PROCESS
	{
		
		if ($Path.length -eq 0)
		{
			
			If ($Pscmdlet.ShouldProcess($destination, "Export sp_configure"))
			{
				$sqlfilename = Export-SqlSpConfigure $sourceserver
			}
			
			if ($sourceserver.versionMajor -ne $destserver.versionMajor -and $force -eq $false)
			{
				Write-Warning "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Use -Force to override this precaution or check the exported sql file, $sqlfilename, and run manually."
				return
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Execute sp_configure"))
			{
				$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				
				$destprops = $destserver.Configuration.Properties
				
				foreach ($sourceprop in $sourceserver.Configuration.Properties)
				{
					$displayname = $sourceprop.DisplayName
					
					$destprop = $destprops | where-object{ $_.Displayname -eq $displayname }
					if ($destprop -ne $null)
					{
						try
						{
							$destprop.configvalue = $sourceprop.configvalue
							$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
							Write-Output "updated $($destprop.displayname) to $($sourceprop.configvalue)"
						}
						catch { Write-Error "Could not $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported." }
					}
				}
				try { $destserver.Configuration.Alter() }
				catch { $needsrestart = $true }
				
				$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
				$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
				$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				
				if ($needsrestart -eq $true)
				{
					Write-Warning "Some configuration options will be updated once SQL Server is restarted."
				}
				else { Write-Output "Configuration option has been updated." }
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Removing temp file"))
			{
				Remove-Item $sqlfilename -ErrorAction SilentlyContinue
			}
			
		}
		else
		{
			If ($Pscmdlet.ShouldProcess($destination, "Importing sp_configure from $Path"))
			{	
				$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$sql = Get-Content $Path
				foreach ($line in $sql)
				{
					try
					{
						$server.ConnectionContext.ExecuteNonQuery($line) | Out-Null; Write-Output "Successfully executed $line"
					}
					catch
					{
						Write-Error "$line failed. Feature may not be supported."
					}
				}
				$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
				Write-Warning "Some configuration options will be updated once SQL Server is restarted."
			}
		}
	}
	END
	{
		if ($Path.length -gt 0) { 
			$server.ConnectionContext.Disconnect() 
		} else {
			$sourceserver.ConnectionContext.Disconnect() 
			$destserver.ConnectionContext.Disconnect() 
		}
	
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
		{
			Write-Output "SQL Server configuration options migration finished"
		}
		
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Import-SqlSpConfigure
	}
}