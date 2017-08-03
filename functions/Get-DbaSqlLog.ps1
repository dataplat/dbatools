function Get-DbaSqlLog {
<#
	.SYNOPSIS
		Gets the "SQL Error Log" of an instance

	.DESCRIPTION
		Gets the "SQL Error Log" of an instance. Returns all 10 error logs by default.

	.PARAMETER SqlInstance
		The SQL Server instance, or instances.

	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

	.PARAMETER LogNumber
		An Int32 value that specifies the index number of the error log required.
		Error logs are listed 0 through 99, where 0 is the current error log and 99 is potential oldest log file.

		SQL Server errorlog rollover defaults to 6, but can be increased to 99. https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/scm-services-configure-sql-server-error-logs

	.PARAMETER Source
		Filter results based on the Source of the error (e.g. Logon, Server, etc.)

	.PARAMETER Text
		Filter results based on a pattern of text (e.g. "login failed", "error: 12345").

	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages

	.NOTES
		Tags: Logging
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
		https://dbatools.io/Get-DbaSqlLog

	.EXAMPLE
		Get-DbaSqlLog -SqlInstance sql01\sharepoint

		Returns every log entry from sql01\sharepoint SQL Server instance.

	.EXAMPLE
		Get-DbaSqlLog -SqlInstance sql01\sharepoint -LogNumber 3, 6

		Returns all log entries for log number 3 and 6 on sql01\sharepoint SQL Server instance.

	.EXAMPLE
		Get-DbaSqlLog -SqlInstance sql01\sharepoint -Source Logon

		Returns every log entry, with a source of Logon, from sql01\sharepoint SQL Server instance.

	.EXAMPLE
		Get-DbaSqlLog -SqlInstance sql01\sharepoint -LogNumber 3 -Text "login failed"

		Returns every log entry for log number 3, with "login failed" in the text, from sql01\sharepoint SQL Server instance.

	.EXAMPLE
		$servers = "sql2014","sql2016", "sqlcluster\sharepoint"
		$servers | Get-DbaSqlLog -LogNumber 0

		Returns the most recent SQL Server error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"
#>
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[ValidateRange(0, 99)]
		[int[]]$LogNumber,
		[object[]]$Source,
		[string]$Text,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"

			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			if ($LogNumber) {
				foreach ($number in $lognumber) {
					foreach ($object in $server.ReadErrorLog($number)) {
						if ($Source -and $object.ProcessInfo -ne $Source) {
							continue
						}
						if ($Text -and $object.Text -notlike "*$Text*") {
							continue
						}
						Write-Message -Level Verbose -Message "Processing $object"
						Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.NetName
						Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
						Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

						# Select all of the columns you'd like to show
						Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, 'ProcessInfo as Source', Text
					}
				}
			}
			else {
				foreach ($object in $server.ReadErrorLog()) {
					if ($Source -and $object.ProcessInfo -ne $Source) {
						continue
					}
					if ($Text -and $object.Text -notlike "*$Text*") {
						continue
					}
					Write-Message -Level Verbose -Message "Processing $object"
					Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.NetName
					Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
					Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

					# Select all of the columns you'd like to show
					Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, 'ProcessInfo as Source', Text
				}
			}
		}
	}
}