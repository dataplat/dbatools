function Get-DbaUptime {

	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[PsCredential]$WindowsCredential,
		[Switch]$SQLOnly

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
                $SQLUptime = New-TimeSpan  -start $SQLStartTime -end  (get-date)
				$SQLUptimeString =  "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)


				if ($SQLOnly -ne $true)
				{
					$ClusterCheck = Get-DbaClusterActiveNode -SqlServer $servername
					if ($ClusterCheck -eq 'Not a clustered instance' )
					{
						$WindowsServerName = ($servername.split("\"))[0]
					}
					else
					{
						$WindowsServerName = $ClusterCheck
					}
					try {
						$WinBootTime = (Get-CimInstance -ClassName win32_operatingsystem -ComputerName $windowsServerName).lastbootuptime
						$WindowsUptime = New-TimeSpan -start $WinBootTime -end (get-date)
						$WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
						
					}
					catch [System.Exception] {
						Write-Exception $_
						#Skip the windows results as they'll either be garbage or not there.
						$SQLOnly = $true
					}

				}
				if ($SQLOnly -eq $true)
				{
					$null = $collection.Add([PSCustomObject]@{
							SQLServer = $servername
							SQLStartTime = $SQLStartTime
							SQLUptimeString = $SQLUptimeString
							SQLUptime = $SQLUptime
					})
				}else{
					$null = $collection.Add([PSCustomObject]@{
							SQLServer = $servername
							SQLStartTime = $SQLStartTime
							SQLUptimeString = $SQLUptimeString
							SQLUptime = $SQLUptime
							WindowsBootTime = $WinBootTime
							WindowsUptime = $WindowsUptime
							WindowsUptimeString = $WindowsUptimeString
					})
				}

        }
    }
    END 
    {
            return $collection
    }
}
