Function Copy-SqlDatabaseMail {
 <#
            .SYNOPSIS
             

            .EXAMPLE
               Copy-SqlDatabaseMail $sourceserver $destserver  
			
        #>
		[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
        param(
			[parameter(Mandatory = $true)]
			[object]$Source,
			[parameter(Mandatory = $true)]
			[object]$Destination,
			[System.Management.Automation.PSCredential]$SourceSqlCredential,
			[System.Management.Automation.PSCredential]$DestinationSqlCredential
		)
	
PROCESS {
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name	
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
	
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	$mail = $sourceserver.mail
	
	If ($Pscmdlet.ShouldProcess($destination,"Migrating all mail objects")) {
		try {
			$sql = $mail.script()
			$sql += $mail.profiles.Script()
			$sql += $mail.accounts.Script()
			$sql += $mail.accounts.mailservers.Script()
			$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
		} catch { 
			if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*exist*') {
				Write-Output "Some mail objects were skipped because they already exist on $destination"
			} else { Write-Output $_.Exception }
		}
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	If ($Pscmdlet.ShouldProcess("local host","Showing finished message")) { Write-Output "Mail migration finished" }
}
}