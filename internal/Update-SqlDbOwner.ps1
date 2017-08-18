Function Update-SqlDbOwner
{
<#
.SYNOPSIS
Internal function. Updates specified database dbowner.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$source,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$destination,
		[string]$dbname,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential
	)
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
	
	$source = $sourceserver.DomainInstanceName
	$destination = $destserver.DomainInstanceName
	
	if ($dbname.length -eq 0)
	{
		$databases = ($sourceserver.Databases | Where-Object { $destserver.databases.name -contains $_.name -and $_.IsSystemObject -eq $false }).Name
	}
	else { $databases = $dbname }
	
	foreach ($dbname in $databases)
	{
		$destdb = $destserver.databases[$dbname]
		$dbowner = $sourceserver.databases[$dbname].owner
		
		if ($destdb.owner -ne $dbowner)
		{
			if ($destdb.Status -ne 'Normal') { Write-Output "Database status not normal. Skipping dbowner update."; continue }
			
			if ($dbowner -eq $null -or $destserver.logins[$dbowner] -eq $null)
			{
				try
				{
					$dbowner = ($destserver.logins | Where-Object { $_.id -eq 1 }).Name
				}
				catch
				{
					$dbowner = "sa"
				}
			}
			
			try
			{
				if ($destdb.ReadOnly -eq $true)
				{
					$changeroback = $true
					Update-SqlDbReadOnly $destserver $dbname $false
				}
				
				$destdb.SetOwner($dbowner)
				Write-Output "Changed $dbname owner to $dbowner"
				
				if ($changeroback)
				{
					Update-SqlDbReadOnly $destserver $dbname $true
					$changeroback = $null
				}
			}
			catch
			{
				Write-Error "Failed to update $dbname owner to $dbowner."
			}
		}
		else { Write-Output "Proper owner already set on $dbname" }
	}
}
