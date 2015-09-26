Function Export-SqlSpConfigure     {
 <#
            .SYNOPSIS
              Exports advanced sp_configure global configuration options to sql file.

            .EXAMPLE
               $outputfile = Export-SqlSpConfigure $sourceserver -Path C:\temp\sp_configure.sql

            .OUTPUTS
                File to disk, and string path.
			
        #>
		[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$SqlServer,
			[string]$Path,
			[System.Management.Automation.PSCredential]$SqlCredential
		)
	PROCESS {	
		$server = Connect-SqlServer $SqlServer $SqlCredential
		
		if ($sqlserver.versionMajor -lt 9) { "Windows 2000 not supported for sp_configure export."; break }
		
		if ($path.length -eq 0) {
			$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
			$path = "$($server.name.replace('\','$'))-$timenow-sp_configure.sql"
		}
		
		try { Set-Content -Path $path "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE" }
		catch { throw "Can't write to $path" }
		
		$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
		$server.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
		foreach ($sourceprop in $server.Configuration.Properties) {
			$displayname = $sourceprop.DisplayName
			$configvalue = $sourceprop.ConfigValue
			Add-Content -Path $path "EXEC sp_configure '$displayname' , $configvalue; RECONFIGURE WITH OVERRIDE"
		}
		$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
		$server.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null	
		return $path
	} 
}

Function Import-SqlSpConfigure     {
 <#
            .SYNOPSIS
              Updates sp_configure settings on destination server.

            .EXAMPLE
                Import-SqlSpConfigure sqlserver sqlcluster $SourceSqlCredential $DestinationSqlCredential
				

            .EXAMPLE
                Import-SqlSpConfigure -SqlServer sqlserver -Path .\spconfig.sql -SqlCredential $SqlCredential
				
            .OUTPUTS
                $true if success
                $false if failure

#>
		[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
        param(
            [object]$Source,
            [object]$Destination,
			[System.Management.Automation.PSCredential]$SourceSqlCredential,
			[System.Management.Automation.PSCredential]$DestinationSqlCredential,
			[object]$SqlServer,
			[string]$Path,
			[System.Management.Automation.PSCredential]$SqlCredential,
			[switch]$Force

		)
	PROCESS {
	
		if ($Path.length -eq 0) {
			$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
			$source = $sourceserver.name
			$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
			$destination = $destserver.name

			if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
			if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
			
			If ($Pscmdlet.ShouldProcess($destination,"Export sp_configure")) {
				$sqlfilename = Export-SqlSpConfigure $sourceserver
			}
		
		
			if ($sourceserver.versionMajor -ne $destserver.versionMajor -and $force -eq $false) {
				Write-Warning "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Use -Force to override this precaution or check the exported sql file, $sqlfilename, and run manually."
				return
			}
		
			If ($Pscmdlet.ShouldProcess($destination,"Execute sp_configure")) {
				$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null

				$destprops = $destserver.Configuration.Properties

				foreach ($sourceprop in $sourceserver.Configuration.Properties) {
					$displayname = $sourceprop.DisplayName
					
					$destprop = $destprops | where-object{$_.Displayname -eq $displayname}
					if ($destprop -ne $null) {
						try { 
							$destprop.configvalue = $sourceprop.configvalue
							$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
							Write-Output "updated $($destprop.displayname) to $($sourceprop.configvalue)"
						} catch { Write-Error "Could not $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported." } 
					}
				}
				try { $destserver.Configuration.Alter() } catch { $needsrestart = $true }
				$sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
				$sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				$destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
				$destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null

				if ($needsrestart -eq $true) { Write-Warning "Some configuration options will be updated once SQL Server is restarted." 
				} else { Write-Output "Configuration option has been updated." }
			}
		} else {
				If ($Pscmdlet.ShouldProcess($destination,"Importing sp_configure from $Path")) {
				$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
				if ((Test-Path $Path) -eq $false) { throw "File Not Found" }
				
				$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
				$sql = Get-Content $Path
				foreach ($line in $sql) {
					try { $server.ConnectionContext.ExecuteNonQuery($line) | Out-Null ; Write-Output "Successfully executed $line"
					} catch { 
						Write-Error "$line failed. Feature may not be supported." }
					}
				$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
				Write-Warning "Some configuration options will be updated once SQL Server is restarted."
			}
		}
	} 
	END { 
		If ($Pscmdlet.ShouldProcess("console","Showing finished message")) {
			Write-Output "SQL Server configuration options migration finished" 
		}
	}
}