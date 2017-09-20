function Get-DbaRegisteredServer {
	<#
		.SYNOPSIS
			Gets list of SQL Server objects stored in SQL Server Central Management Server (CMS).

		.DESCRIPTION
			Returns an array of servers found in the CMS.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Group
			Specifies one or more groups to include from SQL Server Central Management Server.

		.PARAMETER ExcludeGroup
			Specifies one or more Central Management Server groups to exclude.

		.PARAMETER ExcludeCmsServer
			Filters out the CMS you are connected to. This does a full match of the value passed in to `-SqlInstance`
			and the ServerName property of the CMS registration.

		.PARAMETER ResolveNetworkName
			Also return the NetBIOS name and IP addresses(s) of each server.
	
		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Author: Bryan Hamby (@galador)
			Tags: RegisteredServer, CMS

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaRegisteredServer

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a

			Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

			Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

			Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a
	#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Groups")]
		[object[]]$Group,
		[object[]]$ExcludeGroup,
		[switch]$ExcludeCmsServer,
		[switch]$ResolveNetworkName,
		[switch]$Silent
	)
	begin {
		function Find-CmsGroup {
			[OutputType([object[]])]
			[cmdletbinding()]
			param(
				$CmsGrp,
				$Base = $null,
				$Stopat
			)
			$results = @()
			foreach ($el in $CmsGrp) {
				if ($null -eq $Base -or [string]::IsNullOrWhiteSpace($Base) ) {
					$partial = $el.name
				}
				else {
					$partial = "$Base\$($el.name)"
				}
				if ($partial -eq $Stopat) {
					return $el
				}
				else {
					foreach ($elg in $el.ServerGroups) {
						$results += Find-CmsGroup -CmsGrp $elg -Base $partial -Stopat $Stopat
					}
				}
			}
			return $results
		}
		
		$defaults = @()
		if ($ResolveNetworkName) {
			$defaults += 'ComputerName', 'FQDN', 'IPAddress'
		}
		$defaults += 'Name', 'ServerName', 'Description', 'ServerType', 'SecureConnectionString'
		
	}
	
	process {
		if (Test-FunctionInterrupt) { 
			return 
		}

		$servers = @()
		foreach ($instance in $SqlInstance) {
			try {
				$cmsStore = Get-DbaRegisteredServersStore -SqlInstance $instance -SqlCredential $SqlCredential -Silent:$Silent
			}
			catch {
				Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
				return
			}

			if (Test-Bound -ParameterName ExcludeGroup) {
				$Group = ($cmsStore.DatabaseEngineServerGroup.ServerGroups | Where-Object Name -notin $ExcludeGroup).Name
			}

			if ($Group) {
				foreach ($currentGroup in $Group) {
					$cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
					if ($null -eq $cms) {
						Write-Message -Level Output -Message "No groups found matching that name on instance '$instance'."
						continue
					}
					$servers += ($cms.GetDescendantRegisteredServers())
				}
			}
			else {
				$cms = $cmsStore.DatabaseEngineServerGroup
				$servers += ($cms.GetDescendantRegisteredServers())
			}

			if ($ExcludeCmsServer) {
				$servers = ($servers | Where-Object { $_.ServerName -ne $instance})
			}
		}
		
		foreach ($server in $servers) {
			Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $null
			Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $null
			Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null
			
			if ($ResolveNetworkName) {
				try {
					$lookup = Resolve-DbaNetworkName $server.ServerName -Turbo
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $lookup.FQDN
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress
				}
				catch {
					try {
						$lookup = Resolve-DbaNetworkName $server.ServerName
						Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
						Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $lookup.FQDN
						Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress
					} catch {}
				}
			}
			Add-Member -Force -InputObject $server -MemberType ScriptMethod -Name ToString -Value { $this.ServerName }
			Select-DefaultView -InputObject $server -Property $defaults
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-DbaRegisteredServerName
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-SqlRegisteredServerName
	}
}
