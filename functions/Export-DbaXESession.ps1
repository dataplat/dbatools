function Export-DbaXESession {
 <#
	.SYNOPSIS
	Exports a T-SQL Script to create a new session.

	.DESCRIPTION
	Exports a T-SQL Script to create a new session.
	
	.PARAMETER SqlInstance
	The SQL Instances that you're connecting to.

	.PARAMETER SqlCredential
	Credential object used to connect to the SQL Server as a different user

	.PARAMETER Session
	The Name of the session(s) to export

	.PARAMETER Path
	The path to export the file. Can be .sql or directory.
	
	.PARAMETER SessionCollection
	Enables piping sessions

	.PARAMETER Type
	This is a placeholder until we can get XML to work. Right now, the only exports are T-SQL.
	
	.PARAMETER EnableException
	By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
	This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
	Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
	
	.NOTES
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Export-DbaXESession

	.EXAMPLE
	Export-DbaXESession -SqlInstance sql2017 -Path C:\temp\xe
 	Returns a new XE Session object from sql2017 then adds an event, an action then creates it.

	.EXAMPLE
	Get-DbaXESession -SqlInstance sql2017 -Session session_health | Export-DbaXESession -Path C:\temp
 	Returns a new XE Session object from sql2017 then adds an event, an action then creates it.

#>
	[CmdletBinding()]
	param (
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[parameter(Mandatory)]
		[object[]]$Session,
		[string]$Path,
		[Parameter(ValueFromPipeline)]
		[Microsoft.SqlServer.Management.XEvent.Session[]]$SessionCollection,
		[ValidateSet("SQL", "XML")]
		[string]$Type = "SQL",
		[switch]$EnableException
	)
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$SessionCollection += Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session -EnableException
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			foreach ($xes in $SessionCollection) {
				$xesname = $xes.Name
				
				if (-not (Test-Path -Path $Path)) {
					Stop-Function -Message "$Path does not exist" -Target $Path
				}
				
				if ($Type -eq "SQL") {
					if ($path.EndsWith(".sql")) {
						$filename = $path
					}
					else {
						$filename = "$path\$xesname.sql"
					}
					Write-Message -Level Output -Message "Wrote $type for $xesname to $filename"
					$xes.ScriptCreate.GetScript() | Out-File -FilePath $filename -Encoding UTF8 -Append
				}
			}
		}
	}
}