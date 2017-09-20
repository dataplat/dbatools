function Get-DbaRegisteredServerName {
	<#
		.SYNOPSIS
			Gets list of SQL Server objects stored in SQL Server Central Management Server (CMS).

		.DESCRIPTION
			Returns an array of servers found in the CMS. By default, the command returns the ServerName property
			of the servers. You can specify -FullObject to return the full SMO object, -IpAddress for only the
			IPv4 Addresses of the server, and -NetBiosName for only the ComputerName.


		.PARAMETER SQLInstance
			SQL Server instance(s) to connect to.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Group
			Specifies one or more groups to include from SQL Server Central Management Server.

		.PARAMETER ExcludeGroup
			Specifies one or more Central Management Server groups to exclude.

		.PARAMETER NoCmsServer
			If this switch is enabled, the CMS itself is excluded from the output when using NetBiosName,IpAddress or ServerName.
			
			If this switch is not enabled, the CMS will only be included if you do not specify a group.

		.PARAMETER FullObject
			If this switch is enabled, the full SMO RegisteredServer object is returned for each server. An object for the CMS Server will not be returned.

		.PARAMETER NetBiosName
			If this switch is enabled, only the NetBIOS name of each server will be returned.

		.PARAMETER IpAddress
			If this switch is enabled, only the IP address(s) of each server will be returned.

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

			Gets a list of server names from the CMS on sqlserver2014a using Windows Credentials.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -SqlCredential $credential

			Gets a list of server names from the CMS on sqlserver2014a using SQL Authentication.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -NoCmsServer

			Gets a list of server names from the CMS on sqlserver2014a, but excludes the CMS server from the results.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR\Development

			Returns a list of server names in the group Development under the HR group on the CMS on sqlserver2014a

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -IpAddress

			Gets a list of the IP Addresses for servers in the CMS on sqlserver2014a using Windows Credentials.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -NetBiosName

			Gets a list of the NetBIOS names of the servers in the CMS on sqlserver2014a using Windows Credentials.

		.EXAMPLE
			Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -FullObject

			Returns the full SMO RegisteredServer object for servers in the CMS on sqlserver2014a using Windows Credentials.
	#>
	[OutputType([object[]])]
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
	process {
		if ($NoCmsServer -and $FullObject) {
			Write-Message -Level Verbose -Message ("-NoCmsServer is not valid in combination with -FullObject, ignoring. -FullObject does not return an entry for the CMS itself.")
		}

		if (Test-FunctionInterrupt) {
			return
		}

		# see notes at Get-ParamSqlCmsGroups
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

		$servers = @()
		$cmsServers = @()
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance."
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
				$sqlConnection = $server.ConnectionContext.SqlConnectionObject
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			try {
				$cmsStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlConnection)
			}
			catch {
				Stop-Function -Message "Cannot access Central Management Server." -ErrorRecord $_ -Continue
				return
			}
			
			if (Test-Bound -ParameterName ExcludeGroup) {
				$Group = ($cmsStore.DatabaseEngineServerGroup.ServerGroups | Where-Object Name -notin $ExcludeGroup).Name
			}
			
			if ($Group) {
				foreach ($currentGroup in $Group) {
					$cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
					if ($null -eq $cms) {
						Write-Message -Level Output -Message "No groups found matching that name."
						continue
					}
					$servers += ($cms.GetDescendantRegisteredServers())
				}
			}
			else {
				$cms = $cmsStore.ServerGroups["DatabaseEngineServerGroup"]
				$servers += ($cms.GetDescendantRegisteredServers())
			}
			
			#Store some information about the CMSs for later use
			try {
				$ip = (Resolve-DbaNetworkName $server.Name -Turbo -Silent).IpAddress
			}
			catch {
				$ip = $null
			}
			$fakeCms = [PSCustomObject]@{
				ComputerName = $server.ComputerNamePhysicalNetBIOS
				ServerName   = $server.Name
				IPAddress    = $ip
			}
			$cmsServers += $fakeCms
		}
	}
	
	end {
		if ($NetBiosName -or $IpAddress) {
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
		
		$IncludeCmsServer = ($NoCmsServer -eq $false -and $null -eq $Group)

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

		# #If -FullObject is specified, return everything, no distinct
		elseif ($FullObject) {
			return $servers
		}

		#By default, return only the server name for backwards compatibility
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
