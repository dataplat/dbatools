function Get-DbaRegisteredServer {
	<#
		.SYNOPSIS
			Gets list of SQL Server objects stored in SQL Server Central Management Server (CMS).

		.DESCRIPTION
			Returns an array of servers found in the CMS.

<<<<<<< HEAD
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
=======
		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to.
			This can be a collection to allow the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Group
			List of groups to filter to in SQL Server Central Management Server. You can specify one or more, comma separated.
			You can specify a sub-group path with a forward slash (e.g. "group1/subgroup1a")

		.PARAMETER ExcludeGroup
			List of groups to filter out. You can specify one or more, comma separated.
>>>>>>> 4cbb8cdd8262905d00a68a2678866f9a0f22262a

		.PARAMETER ExcludeCmsServer
			Filters out the CMS you are connected to. This does a full match of the value passed in to `-SqlInstance`
			and the ServerName property of the CMS registration.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Original Author (from Get-DbaRegsiteredServerName): Chrissy LeMaire (@cl)
			Author: Bryan Hamby (@galador)
			Tags: RegisteredServer,CMS

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaRegisteredServer

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a

<<<<<<< HEAD
			Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName
=======
			Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential
>>>>>>> 4cbb8cdd8262905d00a68a2678866f9a0f22262a

			Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

			Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

			Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a
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
		[switch]$ExcludeCmsServer,
		[switch]$Silent
	)
	begin {
		function Find-CmsGroup {
<<<<<<< HEAD
			[OutputType([object[]])]
=======
>>>>>>> 4cbb8cdd8262905d00a68a2678866f9a0f22262a
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
	}

	process {
<<<<<<< HEAD
		if (Test-FunctionInterrupt) { 
			return 
		}
=======
		if (Test-FunctionInterrupt) { return }
>>>>>>> 4cbb8cdd8262905d00a68a2678866f9a0f22262a

		$servers = @()
		foreach ($instance in $SqlInstance) {
			try {
				$cmsStore = Get-DbaRegisteredServersStore -SqlInstance $instance -SqlCredential $SqlCredential -Silent:$Silent
			}
			catch {
<<<<<<< HEAD
				Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue
=======
				Stop-Function -Message "Cannot access Central Management Server '$instance'" -ErrorRecord $_ -Continue
>>>>>>> 4cbb8cdd8262905d00a68a2678866f9a0f22262a
				return
			}

			if (Test-Bound -ParameterName ExcludeGroup) {
				$Group = ($cmsStore.DatabaseEngineServerGroup.ServerGroups | Where-Object Name -notin $ExcludeGroup).Name
			}

			if ($Group) {
				foreach ($currentGroup in $Group) {
					$cms = Find-CmsGroup -CmsGrp $cmsStore.DatabaseEngineServerGroup.ServerGroups -Stopat $currentGroup
					if ($null -eq $cms) {
<<<<<<< HEAD
						Write-Message -Level Output -Message "No groups found matching that name on instance '$instance'."
=======
						Write-Message -Level Output -Message "No groups found matching that name on instance '$instance'"
>>>>>>> 4cbb8cdd8262905d00a68a2678866f9a0f22262a
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
			try {
				$lookup = Resolve-DbaNetworkName $server.ServerName -Turbo -Silent
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $lookup.ComputerName
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $lookup.IPAddress -PassThru
			}
			catch {
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -Value $null
				Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null -PassThru
			}
		}
	}
}
