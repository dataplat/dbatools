function Install-DbaWhoIsActive {
<#
	.SYNOPSIS
		Automatically installs or updates sp_WhoisActive by Adam Machanic.
	
	.DESCRIPTION
		This command downloads, extracts and installs sp_WhoisActive with Adam's permission. To read more about sp_WhoisActive, please visit:
		
		Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx
		
		Also, consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate
		
		Note that you will be prompted a bunch of times to confirm an action. To disable this behavior, pass the -Confirm:$false parameter (see example below).
	
	.PARAMETER SqlInstance
		The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.
	
	.PARAMETER SqlCredential
		PSCredential object to connect under. If not specified, current Windows login will be used.
	
	.PARAMETER Database
		The database to install the procedures to.
		This parameter is mandatory when executing this command unattended.
	
	.PARAMETER Update
		Looks online for the most up to date version, replacing the local one.
	
	.PARAMETER Silent
		Replaces user friendly yellow warnings with bloody red exceptions of doom!
		Use this if you want the function to throw terminating errors you want to catch.
	
	.PARAMETER WhatIf
		Shows what would happen if the command were to run. No actions are actually performed.
	
	.PARAMETER Confirm
		Prompts you for confirmation before executing any changing operations within the command.
	
	.EXAMPLE
		Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master
		
		Installs sp_WhoisActive to sqlserver2014a's master database. Logs in using Windows Authentication.
	
	.EXAMPLE
		Install-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $cred
		
		Pops up a dialog box asking which database on sqlserver2014a you want to install the proc to. Logs into SQL Server using SQL Authentication.
		
	
	.EXAMPLE
		Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master -Update
		
		Installs sp_WhoisActive to sqlserver2014a's master database. Forces a retrieval of the script from internet
	
	.EXAMPLE
		$instances = Get-DbaRegisteredServerName sqlserver
		Install-DbaWhoIsActive -SqlInstance $instances -Database master
		
	
	.NOTES
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
	.LINK
		https://dbatools.io/Install-DbaWhoIsActive
#>
	
	[CmdletBinding(SupportsShouldProcess)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[parameter(Mandatory=$false)]
		[ValidateScript({Test-Path -Path $_ -PathType file})]
		[string]$LocalFile,
		[object]$Database,
		[switch]$Silent
	)
	
	begin {
		$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
		$zipfile = "$temp\spwhoisactive.zip"

		if ($LocalFile -eq $null) {
			$baseUrl = "http://whoisactive.com/downloads"
			$latest = ((Invoke-WebRequest -uri http://whoisactive.com/downloads).Links | where-object {$PSItem.href -match "who_is_active"} | Select-Object href -First 1).href	
			if ($PSCmdlet.ShouldProcess($env:computername, "Downloading sp_WhoisActive")) {
				try {
					Write-Message -Level Verbose -Message "Downloading sp_WhoisActive zip file, unzipping and installing."
					$url = $baseUrl + "/" + $latest
					try {
						Invoke-WebRequest $url -OutFile $zipfile -ErrorAction Stop
					}
					catch {
						#try with default proxy and usersettings
						(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
						Invoke-WebRequest $url -OutFile $zipfile -ErrorAction Stop
					}
				} catch {
					Stop-Function -Message "Couldn't download sp_WhoisActive. Please download and install manually from $url." -ErrorRecord $_
					return
				}
			}
		} else {
			# Look local
			if ($LocalFile.EndsWith("zip")) {
				Copy-Item -Path $LocalFile -Destination $zipfile -Force;
			} else {
				Copy-Item -Path $LocalFile -Destination (Join-Path -path $temp -childpath "whoisactivelocal.sql");
			}
		}
		if ($LocalFile -eq $null -or $LocalFile.EndsWith("zip")) {
			# Unpack
			# Unblock if there's a block
			Unblock-File $zipfile -ErrorAction SilentlyContinue
					
			if (Get-Command -ErrorAction SilentlyContinue -Name "Expand-Archive") {
				Expand-Archive -Path $LocalFile -DestinationPath $temp -Force;
			} else {
			# Keep it backwards compatible
				$shell = New-Object -ComObject Shell.Application
				$zipPackage = $shell.NameSpace($zipfile)
				$destinationFolder = $shell.NameSpace($temp)
				Get-ChildItem "$temp\who*active*.sql" | Remove-Item		
				$destinationFolder.CopyHere($zipPackage.Items())
			}					
			Remove-Item -Path $zipfile
			$sqlfile = (Get-ChildItem "$temp\who*active*.sql" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
		} else {
			$sqlfile = $LocalFile;
		}

		if ($PSCmdlet.ShouldProcess($env:computername, "Reading SQL file into memory")) {
			Write-Message -Level Verbose -Message "Using $sqlfile."
			
			$sql = [IO.File]::ReadAllText($sqlfile)
			$sql = $sql -replace 'USE master', ''
			$batches = $sql -split "GO\r\n"
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance."
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if (-not $Database) {
				if ($PSCmdlet.ShouldProcess($instance, "Prompting with GUI list of databases")) {
					$Database = Show-DbaDatabaseList -SqlInstance $server -Title "Install sp_WhoisActive" -Header "To deploy sp_WhoisActive, select a database or hit cancel to quit." -DefaultDb "master"
					
					if (-not $Database) {
						Stop-Function -Message "You must select a database to install the procedure." -Target $Database
						return
					}
					
					if ($Database -ne 'master') {
						Write-Message -Level Warning -Message "You have selected a database other than master. When you run Invoke-DbaWhoIsActive in the future, you must specify -Database $Database."
					}
				}
			}
			
			if ($PSCmdlet.ShouldProcess($instance, "Installing sp_WhoisActive")) {
				$allprocedures_query = "select name from sys.procedures where is_ms_shipped = 0"
				$databases = $server.Databases | Where-Object Name -eq $Database
				if ($databases.Count -eq 0) {
					Stop-Function -Message "Failed to find database $Database on $instance." -ErrorRecord $_ -Continue -Target $instance
				}
				$allprocedures = ($server.Query($allprocedures_query, $Database)).Name
				foreach ($batch in $batches) {
					try {
						$null = $server.databases[$Database].ExecuteNonQuery($batch)
					}
					catch {
						Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance
					}
				}
				$baseres = @{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Database = $Database
					Name = 'sp_WhoisActive'
				}
				if ('sp_WhoisActive' -in $allprocedures) {
					$status = 'Updated'
				}
				else {
					$status = 'Installed'
				}
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Database = $Database
					Name = 'sp_WhoisActive'
					Status = $status
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Install-SqlWhoIsActive
	}
}
