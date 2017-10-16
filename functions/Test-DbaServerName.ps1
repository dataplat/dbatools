function Test-DbaServerName {
	<#
		.SYNOPSIS
			Tests to see if it's possible to easily rename the server at the SQL Server instance level, or if it even needs to be changed.

		.DESCRIPTION
			When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

			This command helps determine if your OS and SQL Server names match, and whether a rename is required.

			It then checks conditions that would prevent a rename, such as database mirroring and replication.

			https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -Credential parameter.

			Windows Authentication will be used if Credential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Detailed
			If this switch is enabled, additional details are returned including whether the server name is updatable. If the server name is not updatable, the reason why will be returned.

		.PARAMETER NoWarning
			If this switch is enabled, no warning will be displayed if SQL Server Reporting Services can't be checked due to a failure to connect via Get-Service.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: SPN, ServerName
			dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
			Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaServerName

		.EXAMPLE
			Test-DbaServerName -SqlInstance sqlserver2014a

			Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a.

		.EXAMPLE
			Test-DbaServerName -SqlInstance sqlserver2014a, sql2016

			Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

		.EXAMPLE
			Test-DbaServerName -SqlInstance sqlserver2014a, sql2016 -Detailed

			Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

			If a Rename is required, it will also show Updatable, and Reasons if the servername is not updatable.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.ArrayList])]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstance[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[switch]$Detailed,
		[switch]$NoWarning,
		[switch]$Silent
	)

	begin {
		Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
	}
	process {

		foreach ($instance in $SqlInstance) {
			Write-Verbose "Attempting to connect to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			if ($server.IsClustered) {
				Write-Message -Level Warning -Message  "$instance is a cluster. Renaming clusters is not supported by Microsoft."
			}

			$sqlInstanceName = $server.Query("SELECT @@servername AS ServerName").ServerName
			$instance = $server.InstanceName

			if ($instance.Length -eq 0) {
				$serverInstanceName = $server.NetName
				$instance = "MSSQLSERVER"
			}
			else {
				$netname = $server.NetName
				$serverInstanceName = "$netname\$instance"
			}

			$serverInfo = [PSCustomObject]@{
				ComputerName   = $server.NetName
				InstanceName   = $server.ServiceName
				SqlInstance    = $server.DomainInstanceName
				IsEqual        = $serverInstanceName -eq $sqlInstanceName
				RenameRequired = $serverInstanceName -ne $sqlInstanceName
				Updatable      = "N/A"
				Warnings       = $null
				Blockers       = $null
			}

			$reasons = @()
			$serverName = "SQL Server Reporting Services ($instance)"
#			$netBiosName = $server.ComputerNamePhysicalNetBIOS

			Write-Message -Level Verbose -Message "Checking for $serverName on $netBiosName"
			$rs = $null
			try {
				$resolved = Resolve-DbaNetworkName -ComputerName $instance.ComputerName
				$rs = Get-DbaSqlService Get-Service -ComputerName $netBiosName -DisplayName $serverName -ErrorAction SilentlyContinue
			}
			catch {
				if ($NoWarning -eq $false) {
					Write-Message -Level Warning -Message  "Can't contact $netBiosName using Get-Service. This means the script will not be able to automatically restart SQL Services."
				}
			}

			if ($rs.Length -gt 0) {
				if ($rs.Status -eq 'Running') {
					$rstext = "Reporting Services ($instance) must be stopped and updated."
				}
				else {
					$rstext = "Reporting Services ($instance) exists. When it is started again, it must be updated."
				}
				$serverInfo.Warnings = $rstext
			}
			else {
				$serverInfo.Warnings = "N/A"
			}

			# check for mirroring
			$mirroredDb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }

			Write-Debug "Found the following mirrored dbs: $($mirroredDb.Name)"

			if ($mirroredDb.Length -gt 0) {
				$dbs = $mirroredDb.Name -join ", "
				$reasons += "Databases are being mirrored: $dbs"
			}

			# check for replication
			$sql = "SELECT name FROM sys.databases WHERE is_published = 1 OR is_subscribed = 1 OR is_distributor = 1"
			Write-Message -Level Debug -Message "SQL Statement: $sql"
			$replicatedDb = $server.Query($sql)

			if ($replicatedDb.Count -gt 0) {
				$dbs = $replicatedDb.Name -join ", "
				$reasons += "Database(s) are involved in replication: $dbs"
			}

			# check for even more replication
			$sql = "SELECT srl.remote_name as RemoteLoginName FROM sys.remote_logins srl JOIN sys.sysservers sss ON srl.server_id = sss.srvid"
			Write-Message -Level Debug -Message "SQL Statement: $sql"
			$results = $server.Query($sql)

			if ($results.RemoteLoginName.Count -gt 0) {
				$remoteLogins = $results.RemoteLoginName -join ", "
				$reasons += "Remote logins still exist: $remoteLogins"
			}

			if ($reasons.Length -gt 0) {
				$serverInfo.Updatable = $false
				$serverInfo.Blockers = $reasons
			}
			else {
				$serverInfo.Updatable = $true
				$serverInfo.Blockers = "N/A"
			}

			if ($detailed) {
				$serverInfo
			}
			else {
				Select-DefaultView -InputObject $serverInfo -ExcludeProperty Warnings, Blockers
			}
		}
	}
}