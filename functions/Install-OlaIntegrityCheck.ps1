Function Install-OlaIntegrityCheck
{
<#

#>
	
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$Path,
		[ValidateSet('CHECKDB', 'CHECKFILEGROUP', 'CHECKTABLE', 'CHECKALLOC', 'CHECKCATALOG', 'CHECKALLOC', 'CHECKCATALOG')]
		[string[]]$CheckCommands,
		[switch]$PhysicalOnly,
		[switch]$NoIndex,
		[switch]$ExtendedLogicalChecks,
		[switch]$TabLock,
		[string]$FileGroups,
		[string]$Objects,
		[int]$LockTimeout,
		[switch]$LogToTable,
		[switch]$OutputOnly
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamInstallDatabase -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -RegularUser
		$source = $sourceserver.DomainInstanceName
		
		$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		
		switch ($OutputOnly)
		{
			$true { $Execute = $false }
			$false { $Execute = $true }
		}
	
		
		Function Get-OlaMaintenanceSolution
		{
			
			$url = 'https://ola.hallengren.com/scripts/IndexOptimize.sql'
			$sqlfile = "$temp\IndexOptimize.sql"
			
			try
			{
				Invoke-WebRequest $url -OutFile $sqlfile
			}
			catch
			{
				#try with default proxy and usersettings
				(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
				Invoke-WebRequest $url -OutFile $sqlfile
			}
			
			# Unblock if there's a block
			Unblock-File $sqlfile -ErrorAction SilentlyContinue
			
			return $sqlfile
		}
		
		# Used a dynamic parameter? Convert from RuntimeDefinedParameter object to regular array
		$installdatabase = $psboundparameters.InstallDatabase
		
		if ($Header -like '*update*')
		{
			$action = "update"
		}
		else
		{
			$action = "install"
		}
		
		$textinfo = (Get-Culture).TextInfo
		$actiontitle = $textinfo.ToTitleCase($action)
		
		if ($action -eq "install")
		{
			$actioning = "installing"
		}
		else
		{
			$actioning = "updating"
		}
		
		
	}
	
	PROCESS
	{
		
		if ($installdatabase.length -eq 0)
		{
			$installdatabase = Show-SqlDatabaseList -SqlServer $sourceserver -Title "$actiontitle MaintenancePlan" -Header $header -DefaultDb "master"
			
			if ($installdatabase.length -eq 0)
			{
				throw "You must select a database to $action the procedure"
			}
		}
		
		if ($Path.Length -eq 0)
		{
			$sqlfile = "$temp\MaintenanceSolution.sql"
			$path = $sqlfile.FullName
			
			$exists = Test-Path -Path $path
			
			if ($exists -eq $false -or $force -eq $true)
			{
				try
				{
					Write-Output "Downloading MaintenancePlan and $actioning."
					Get-OlaMaintenanceSolution
				}
				catch
				{
					throw "Couldn't download MaintenancePlan. Please download and $action manually from https://ola.hallengren.com/scripts/MaintenanceSolution.sql"
				}
			}
		}
		
		if ((Test-Path $Path) -eq $false)
		{
			throw "Invalid path at $path"
		}
		
		$sql = [IO.File]::ReadAllText($path)
		$sql = $sql -replace 'USE master', ''
		$batches = $sql -split "GO\r\n"
		
		foreach ($batch in $batches)
		{
			try
			{
				$null = $sourceserver.databases[$installdatabase].ExecuteNonQuery($batch)
				
			}
			catch
			{
				Write-Exception $_
				throw "Can't $action stored procedure. See exception text for details."
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		
		if ($OutputDatabaseName -eq $true)
		{
			return $installdatabase
		}
		else
		{
			Write-Output "Finished $actioning MaintenancePlan in $installdatabase on $SqlServer "
		}
	}
}