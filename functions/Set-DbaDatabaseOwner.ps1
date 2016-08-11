function Set-DbaDatabaseOwner {
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
        [object[]]$Databases,
        [string]$TargetLogin = 'sa'
	)

    BEGIN{

		Write-Verbose "Connecting to $SqlServer"
		$server = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
        
        #Validate login
        if(($server.Logins.Name) -notcontains $TargetLogin){
            throw "Invalid login: $TargetLogin"
            return $null
        }
    }
    PROCESS{
        Write-Verbose "Gathering databases to update"
        if($Databases){
            $check = (($databases -join ',') -split ',')
            $dbs = $server.Databases | Where-Object {$_.Owner -ne $TargetLogin -and $check -contains $_.Name }
        } else { 
            $dbs = $server.Databases | Where-Object {$_.Owner -ne $TargetLogin}
        }

        Write-Verbose "Updating $($dbs.Count) database(s)."
        foreach($db in $dbs){
            If($PSCmdlet.ShouldProcess($db,"Setting database owner to $TargetLogin")){
                try{
                    $db.SetOwner($TargetLogin)
                } catch {
                    # write-exception writes the full exception to file
					Write-Exception $_
					throw $_
                }
            }
        }
    }
    END{
        Write-Verbose "Closing connection"
        $server.ConnectionContext.Disconnect()
    }
}