function Get-DbaRegisteredServerName {
	<#
		.SYNOPSIS
			Gets list of SQL Server objects stored in SQL Server Central Management Server (CMS).

		.DESCRIPTION
			Returns an array of servers found in the CMS. By default, the command returns the ServerName property
			of the servers. -IpAddress for only the IPv4 Addresses of the server, and -NetBiosName for only the ComputerName.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to.
			This can be a collection to allow the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Group
			List of groups to filter to in SQL Server Central Management Server. You can specify one or more, comma separated.

		.PARAMETER ExcludeGroup
			List of groups to filter out. You can specify one or more, comma separated.

		.PARAMETER NoCmsServer
			Excludes the CMS itself from returning in the output.
			Without this parameter, the CMS will only be included if you do not specify a group.

		.PARAMETER NetBiosName
			Returns only the NetBios names of each server.

		.PARAMETER IpAddress
			Returns only the IP addresses of each server.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: RegisteredServer,CMS

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaRegisteredServerName

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a

			Gets a list of server names from the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -SqlCredential $credential

			Gets a list of server names from the CMS on sqlserver2014a, using SQL Authentication

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of server names in the HR and Accounting groups from the CMS on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR\Development

			Returns a list of server names in the HR and sub-group Development from the CMS on sqlserver2014a

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -IpAddress

			Gets a list of the IP Addresses for servers in the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -NetBiosName

			Gets a list of the NetBIOS names of the servers in the CMS on sqlserver2014a, using Windows Credentials
	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Groups")]
		[object[]]$Group,
		[object[]]$ExcludeGroup,
		[switch]$NoCmsServer,
		[parameter(ParameterSetName = "NetBios")]
		[switch]$NetBiosName,
		[parameter(ParameterSetName = "IP")]
		[switch]$IpAddress,
		[parameter(ParameterSetName = "FullObject")]
		[switch]$FullObject,
		[switch]$Silent
	)
	begin {
		if ($FullObject) {
			Write-Message -Level Warning -Message "To return the full object, use the function Get-DbaRegisteredServer instead."
			return
		}

		$servers = Get-DbaRegisteredServer -SqlInstance $SqlInstance -SqlCredential $SqlCredential `
			-Group $Group -ExcludeGroup $ExcludeGroup -Silent:$Silent
	}

	process {
		if (Test-FunctionInterrupt) { return }

		#Store some information about the CMS's for later use
		$cmsServers = @()
		foreach ($instance in $SqlInstance) {
			try {
				$lookup = (Resolve-DbaNetworkName $instance -Turbo -Silent)
				$fakeCms = [PSCustomObject]@{
					ComputerName = $lookup.ComputerName
					ServerName   = $lookup.InputName
					IPAddress    = $lookup.IPAddress
				}
				$cmsServers += $fakeCms
			}
			catch {
				#Just skip it if resolving fails
			}
		}
	}
	
	end {
		$IncludeCmsServer = ($NoCmsServer -eq $false -and $null -eq $Group)

		if ($IpAddress -or $NetBiosName) {
			# Use Resolve-DbaNetworkName to get IP / ComputerName
			foreach ($server in $servers) {
				try {
					$lookup = Resolve-DbaNetworkName $server.ServerName -Turbo -Silent
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress
				}
				catch {
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $null
					Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null
				}
			}
		}

		if ($IpAddress) {
			$ret = @($servers | Select-Object IPAddress)

			if ($IncludeCmsServer) {
				$ret += @($cmsServers | Select-Object IPAddress)
			}

			$ret | Select-Object -Unique -ExpandProperty IPAddress
		}

		elseif ($NetBiosName) {
			$ret = @($servers | Select-Object ComputerName)

			if ($IncludeCmsServer) {
				$ret += @($cmsServers | Select-Object ComputerName)
			}

			$ret | Select-Object -Unique -ExpandProperty ComputerName
		}

		#Return only the distinct names of the servers
		else {
			$ret = @($servers | Select-Object ServerName)

			if ($IncludeCmsServer) {
				$ret += @($cmsServers | Select-Object ServerName)
			}

			$ret | Select-Object -Unique -ExpandProperty ServerName
		}

		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlRegisteredServerName
	}
}
