function Get-DbaUptime {

	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[PsCredential]$WindowsCredential
	)

    	BEGIN
	{
        $functionname = "Get-DBAUptime"
		$collection = New-Object System.Collections.ArrayList
	}
    	PROCESS
	{
		$servercount = ++$i
		foreach ($servername in $SqlServer)
		{
            write-verbose "$functionname - server = $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer "$servername" -SqlCredential $Credential
			}
			catch
			{
				if ($servercount -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}
			
			if ($server.VersionMajor -lt 9)
			{
				if ($servercount -eq 1)
				{
					throw "SQL Server 2000 not supported."
				}
				else
				{
					Write-Warning "SQL Server 2000 not supported. Skipping $servername."
					Continue
				}
			}
                #Get TempDB creation date
                $SQLStartTime = $server.Databases["TempDB"].CreateDate
                $SQLUptime = (get-date) - $SQLStartTime
                $WindowsUptime = $WindowsUptime

                #Get Windows Boot date
                
                $winsrv = ($SqlServer.split("\"))[0]
                $OSWmi = Get-WmiObject win32_operatingsystem -ComputerName $winsrv -Credential:$WindowsCredential
                $WinBootTime = $OSWmi.ConvertToDateTime($OSWmi.LastBootupTime)
                $WindowsUptime = (get-date)-$WinBotTime
                $null = $collection.Add([PSCustomObject]@{
				        SQLServer = $servername
						SQLStartTime = $SQLStartTime
                        SQLUptime = $SQLUptime
                        WindowsBootTime = $WinBootTime
                        WindowsUptime = $WindowsUptime
                })

        }
    }
    END 
    {
            return $collection
    }
}
