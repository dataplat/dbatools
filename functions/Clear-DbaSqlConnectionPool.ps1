Function Clear-DbaSqlConnectionPool
{
<#
	.SYNOPSIS
		Resets (or empties) the connection pool.

	.DESCRIPTION

		This command resets (or empties) the connection pool. 
		
		If there are connections in use at the time of the call, they are marked appropriately and will be discarded (instead of being returned to the pool) when Close() is called on them.

		Ref: https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.clearallpools(v=vs.110).aspx

	.PARAMETER ComputerName
		Target computer(s). If no computer name is specified, the local computer is targeted

	.PARAMETER Credential
		Alternate credential object to use for accessing the target computer(s).

	.NOTES
		Tags: WSMan

		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
		https://dbatools.io/Clear-DbaSqlConnectionPool

	.EXAMPLE
		Clear-DbaSqlConnectionPool

		Clears all local connection pools.

	.EXAMPLE
		Clear-DbaSqlConnectionPool -ComputerName workstation27

		Clears all connection pools on workstation27.

#>
	
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("cn", "host", "Server")]
		[string[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]
		$Credential
	)
	
	process
	{
		# TODO: https://jamessdixon.wordpress.com/2013/01/22/ado-net-and-connection-pooling
		
		ForEach ($Computer in $Computername)
		{
			If ($Computer -ne $env:COMPUTERNAME -and $Computer -ne "localhost" -and $Computer -ne "." -and $Computer -ne "127.0.0.1")
			{
				Write-Verbose "Clearing all pools on remote computer $Computer"
				if ($credential)
				{
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
				else
				{
					Invoke-Command2 -ComputerName $computer -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
			}
			else
			{
				Write-Verbose "Clearing all local pools"
				if ($credential)
				{
					Invoke-Command2 -Credential $Credential -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
				else
				{
					Invoke-Command2 -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
			}
		}
	}
}
