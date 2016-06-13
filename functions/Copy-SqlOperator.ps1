Function Copy-SqlOperator
{
<#
.SYNOPSIS 
Copy-SqlOperator migrates operators from one SQL Server to another. 

.DESCRIPTION
By default, all operators are copied. The -Operators parameter is autopopulated for command-line completion and can be used to copy only specific operator s.

If the associated credential for the does not exist on the destination, it will be skipped. If the operator already exists on the destination, it will be skipped unless -Force is used.  

.EXAMPLE   
Copy-SqlOperator -Source sqlserver2014a -Destination sqlcluster

Copies all operators from sqlserver2014a to sqlcluster, using Windows credentials. If operators with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlOperator -Source sqlserver2014a -Destination sqlcluster -Operator PSOperator -SourceSqlCredential $cred -Force

Copies a single operator, the PSOperator operator from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster. If an operator with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlOperator -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[string[]]$Operators,
		[switch]$Force
	)
	
	PROCESS
	{
		$operators = $psboundparameters.Operators
		
		$serveroperators = $sourceserver.JobServer.Operators
		$destoperators = $destserver.JobServer.Operators
		
		$failsafe = $server.jobserver.alertsystem | Select failsafeoperator
		
		foreach ($operator in $serveroperators)
		{
			$operatorname = $operator.name
			if ($operators.length -gt 0 -and $operators -notcontains $operatorname) { continue }
			
			if ($destoperators.name -contains $operator.name)
			{
				if ($force -eq $false)
				{
					Write-Warning "Operator $operatorname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					if ($failsafe.FailSafeOperator -eq $operatorname)
					{
						Write-Warning "$operatorname is the failsafe operator. Skipping drop."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping operator $operatorname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping Operator $operatorname"
							$destserver.jobserver.operators[$operatorname].Drop()
						}
						catch 
						{ 
							Write-Exception $_ 
							continue
						}
					}
				}
			}

			If ($Pscmdlet.ShouldProcess($destination, "Creating Operator $operatorname"))
			{
				try
				{
					Write-Output "Copying Operator $operatorname"
					$sql = $operator.Script() | Out-String
					$sql = $sql -replace "'$source'", "'$destination'"
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Operator migration finished" }
	}
}