function Get-DbaLogin {
	<#
		.SYNOPSIS
			Function to get an SMO login object of the logins for a given SQL Instance. Takes a server object from the pipe

		.DESCRIPTION
			The Get-DbaLogin function returns an SMO Login object for the logins passed, if there are no users passed it will return all logins.

		.PARAMETER SqlInstance
			The SQL Server instance, or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

		.PARAMETER Login
			The login(s) to process - this list is autopopulated from the server. If unspecified, all logins will be processed.

		.PARAMETER ExcludeLogin
			The login(s) to exclude - this list is autopopulated from the server

		.PARAMETER Locked
			Filters on the SMO property to return locked Logins.

		.PARAMETER Disabled
			Filters on the SMO property to return disabled Logins.

		.PARAMETER HasAccess
			Filters on the SMO property to return Logins that has access to the instance of SQL Server.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Original Author: Mitchell Hamann (@SirCaptainMitch)
			Author: Klaas Vandenberghe (@powerdbaklaas)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaLogin

		.EXAMPLE
			Get-DbaLogin -SqlInstance sql2016

			Gets all the logins from server sql2016 using NT authentication and returns the SMO login objects

		.EXAMPLE
			Get-DbaLogin -SqlInstance sql2016 -SqlCredential $sqlcred

			Gets all the logins for a given SQL Server using a passed credential object and returns the SMO login objects

		.EXAMPLE
			Get-DbaLogin -SqlInstance sql2016 -SqlCredential $sqlcred -Login dbatoolsuser,TheCaptain

			Get specific logins from server sql2016 returned as SMO login objects.

		.EXAMPLE
			Get-DbaLogin -SqlInstance sql2016 -ExcludeLogin dbatoolsuser

			Get all user objects from server sql2016 except the login dbatoolsuser, returned as SMO login objects.

		.EXAMPLE
			'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred

			Using Get-DbaLogin on the pipeline, you can also specify which names you would like with -Login.

		.EXAMPLE
			'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -Locked

			Using Get-DbaLogin on the pipeline to get all locked logins on servers sql2016 and sql2014.

		.EXAMPLE
			'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -HasAccess -Disabled

			Using Get-DbaLogin on the pipeline to get all Disabled logins that have access on servers sql2016 or sql2014.
	#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[object[]]$Login,
		[object[]]$ExcludeLogin,
		[switch]$HasAccess,
		[switch]$Locked,
		[switch]$Disabled,
		[switch]$Silent
	)

	process {
		foreach ($Instance in $sqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			$serverLogins = $server.Logins

			if ($Login) {
				$serverLogins = $serverLogins | Where-Object Name -in $Login
			}

			if ($ExcludeLogin) {
				$serverLogins = $serverLogins | Where-Object Name -NotIn $ExcludeLogin
			}

			if ($HasAccess) {
				$serverLogins = $serverLogins | Where-Object HasAccess
			}

			if ($Locked) {
				$serverLogins = $serverLogins | Where-Object IsLocked
			}

			if ($Disabled) {
				$serverLogins = $serverLogins | Where-Object IsDisabled
			}

			foreach ($serverLogin in $serverlogins) {
				Write-Message -Level Verbose -Message "Processing $serverLogin on $instance"

				if ($server.VersionMajor -gt 9) {
					# There's no reliable method to get last login time with SQL Server 2000, so only show on 2005+
					Write-Message -Level Verbose -Message "Getting last login time"
					$sql = "SELECT MAX(login_time) AS [login_time] FROM sys.dm_exec_sessions WHERE login_name = '$($serverLogin.name)'"
					Add-Member -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $server.ConnectionContext.ExecuteScalar($sql)
				}
				else 
				{
					Add-Member -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $null
				}

				Add-Member -InputObject $serverLogin -MemberType NoteProperty -Name ComputerName -Value $server.NetName
				Add-Member -InputObject $serverLogin -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
				Add-Member -InputObject $serverLogin -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName

				Select-DefaultView -InputObject $serverLogin -Property ComputerName, InstanceName, SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled
			} #foreach serverlogin
		} #foreach instance
	} #process
} #function
