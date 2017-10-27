Function Set-DbaMaxMemory {
	<# 
        .SYNOPSIS 
            Sets SQL Server 'Max Server Memory' configuration setting to a new value then displays information this setting. 

        .DESCRIPTION
            Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings. 

            Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to 
            determine the default optimum RAM to use, then sets the SQL max value to that number.

            Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may 
            be going on in your specific environment.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER MaxMB
            Specifies the max megabytes

        .PARAMETER SqlCredential 
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
          
            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.  
         
            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials 
        	being passed as credentials. To connect as a different Windows user, run PowerShell as that user. 

        .PARAMETER Collection
            Results of Get-DbaMaxMemory to be passed into the command
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
            
        .PARAMETER WhatIf
            Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.

        .EXAMPLE 
            Set-DbaMaxMemory sqlserver1

            Set max memory to the recommended MB on just one server named "sqlserver1"

        .EXAMPLE 
            Set-DbaMaxMemory -SqlInstance sqlserver1 -MaxMB 2048

            Explicitly max memory to 2048 MB on just one server, "sqlserver1"

        .EXAMPLE 
            Get-DbaRegisteredServer -SqlInstance sqlserver | Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory

            Find all servers in SQL Server Central Management server that have Max SQL memory set to higher than the total memory 
            of the server (think 2147483647), then pipe those to Set-DbaMaxMemory and use the default recommendation.

		.NOTES
			Tags:  
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK 
            https://dbatools.io/Set-DbaMaxMemory
    #>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param (
		[Parameter(Position = 0)]
		[Alias("ServerInstance", "SqlServer", "SqlServers", "ComputerName")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Parameter(Position = 1)]
		[int]$MaxMB,
		[Parameter(ValueFromPipeline = $True)]
		[object]$Collection,
		[switch][Alias('Silent')]$EnableException
	)
	process {
		if ((Test-Bound -Not -Parameter SqlInstance) -and (Test-Bound -Not -Parameter Collection)) {
			Stop-Function -Category InvalidArgument -Message "You must specify a server list source using -SqlInstance or you can pipe results from Test-DbaMaxMemory"
			return
		}
		
		if ($MaxMB -eq 0) {
			$UseRecommended = $true
		}
		
		if ((Test-Bound -Not -Parameter Collection)) {
			$Collection = Test-DbaMaxMemory -SqlInstance $sqlinstance -SqlCredential $SqlCredential
		}
		
		# We ignore errors, because this will error if we pass the same collection items twice.
		# Given that it is an engine internal command, there is no other plausible error it could encounter.
		$Collection | Add-Member -Force -NotePropertyName OldMaxValue -NotePropertyValue 0 -ErrorAction Ignore
		
		foreach ($currentserver in $Collection) {
			if ($currentserver.server -eq $null) {
				$currentserver = Test-DbaMaxMemory -SqlInstance $currentserver
				$currentserver | Add-Member -Force -NotePropertyName OldMaxValue -NotePropertyValue 0
			}
			
			Write-Message -Level Verbose -Message "Attempting to connect to $server"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $currentserver.server -SqlCredential $SqlCredential -ErrorAction Stop
			}
			catch {
				Stop-Function -Message "Can't connect to $server or access denied. Skipping." -Category ConnectionError -ErrorRecord $_ -Target $currentserver -Continue
			}
			
			if (!(Test-SqlSa -SqlInstance $server)) {
				Stop-Function -Message "Not a sysadmin on $server. Skipping." -Category PermissionDenied -ErrorRecord $_ -Target $currentserver -Continue
			}
			
			$currentserver.OldMaxValue = $currentserver.SqlMaxMB
			
			try {
				if ($UseRecommended) {
					Write-Message -Level Verbose -Message "Changing $server SQL Server max from $($currentserver.SqlMaxMB) to $($currentserver.RecommendedMB) MB"
					
					if ($currentserver.RecommendedMB -eq 0 -or $currentserver.RecommendedMB -eq $null) {
						$maxmem = (Test-DbaMaxMemory -SqlInstance $server).RecommendedMB
						Write-Warning $maxmem
						$server.Configuration.MaxServerMemory.ConfigValue = $maxmem
					}
					else {
						
						$server.Configuration.MaxServerMemory.ConfigValue = $currentserver.RecommendedMB
					}
				}
				else {
					Write-Message -Level Verbose -Message "Changing $server SQL Server max from $($currentserver.SqlMaxMB) to $MaxMB MB"
					$server.Configuration.MaxServerMemory.ConfigValue = $MaxMB
				}
				if ($PSCmdlet.ShouldProcess($currentserver.Server, "Changing maximum memory from $($currentserver.OldMaxValue) to $($server.Configuration.MaxServerMemory.ConfigValue)")) {
					try {
						$server.Configuration.Alter()
						$currentserver.SqlMaxMB = $server.Configuration.MaxServerMemory.ConfigValue
					}
					catch {
						Stop-Function -Message "Failed to apply configuration change for $server" -ErrorRecord $_ -Target $currentserver -Continue
					}
				}
			}
			catch {
				Stop-Function -Message "Could not modify Max Server Memory for $server" -ErrorRecord $_ -Target $currentserver -Continue
			}
			Add-Member -InputObject $currentserver -Force -MemberType NoteProperty -Name CurrentMaxValue -Value $currentserver.SqlMaxMB
			Select-DefaultView -InputObject $currentserver -Property ComputerName, InstanceName, SqlInstance, TotalMB, OldMaxValue, CurrentMaxValue
		}
	}
}