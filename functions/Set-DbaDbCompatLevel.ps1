function Set-DbaDbCompatLevel {
	<#
    .SYNOPSIS
        Change the compatibility level for user database(s).

    .DESCRIPTION
        Change the current Database Compatability Level for all user databases on a server or list of user databases passed in to the function.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlCredential object used to connect to the SQL Server as a different user.

    .PARAMETER Database
        The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

	.PARAMETER CompatabilityLevel
		The compatability level version to change the databases to.

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Update database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Compatability, Database
        Author: Garry Bargsley, http://blog.garrybargsley.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbCompatLevel

    .EXAMPLE
        PS C:\> Set-DbaDbCompatLevel -SqlInstance localhost\sql2017

        Changes Database Compatability Level for all user databases on server localhost\sql2017 that have a compatability level that do not match

    .EXAMPLE
        PS C:\> Set-DbaDbCompatLevel -SqlInstance localhost\sql2017 -CompatabilityLevel 12

        Changes Database Compatability Level for all user databases on server localhost\sql2017 to Version120

    .EXAMPLE
        PS C:\> Set-DbaDbCompatLevel -SqlInstance localhost\sql2017 -Database Test -CompatabilityLevel 12

        Changes Database Compatability Level for database Test on server localhost\sql2017 to Version 120
#>
	[CmdletBinding(SupportsShouldProcess)]
	param (
		[parameter(Position = 0)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[object[]]$Database,
		[int]$CompatabilityLevel,
		[parameter(ValueFromPipeline)]
		[Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
		[Alias('Silent')]
		[switch]$EnableException
	)
	process {

		if (Test-Bound -not 'SqlInstance', 'InputObject') {
			Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection"
			continue
		}

		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
				$server.ConnectionContext.StatementTimeout = [Int32]::MaxValue
			}
			catch {
				Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
			}
			$InputObject += $server.Databases | Where-Object IsAccessible
		}

		$InputObject = $InputObject | Where-Object { $_.IsSystemObject -eq $false }
		if ($Database) {
			$InputObject = $InputObject | Where-Object { $_.Name -contains $Database }
		}

		foreach ($db in $InputObject) {
			$server = $db.Parent
			$ServerVersion = $server.VersionMajor
			Write-Message -Level Verbose -Message "SQL Server is using Version: $ServerVersion"

			$ogcompat = $db.CompatibilityLevel
			$dbversion = switch ($db.CompatibilityLevel) {
				"Version100" { 10 } # SQL Server 2008
				"Version110" { 11 } # SQL Server 2012
				"Version120" { 12 } # SQL Server 2014
				"Version130" { 13 } # SQL Server 2016
				"Version140" { 14 } # SQL Server 2017
				"Version150" { 15 } # SQL Server 2019
				default { 9 } # SQL Server 2005
			}

			if (!$CompatabilityLevel) {
				Write-Message -Level Verbose -Message "Updating $db compatibility to SQL Instance level"
				if ($dbversion -lt $ServerVersion) {
					If ($Pscmdlet.ShouldProcess($server, "Updating $db version on $server from $dbversion to $ServerVersion")) {
						$Comp = $ServerVersion * 10
						$tsqlComp = "ALTER DATABASE $db SET COMPATIBILITY_LEVEL = $Comp"
						try {
							$db.ExecuteNonQuery($tsqlComp)
							$comResult = $Comp
						}
						catch {
							Write-Message -Level Warning -Message "Failed to change Compatibility Level" -ErrorRecord $_ -Target $instance
							$comResult = "Fail"
						}
					}
				}
				else {
					$comResult = "No change"
				}
			}
			else {
				Write-Message -Level Verbose -Message "Updating $db compatibility to $CompatabilityLevel"
					If ($Pscmdlet.ShouldProcess($server, "Updating $db version on $server from $dbversion to $CompatabilityLevel")) {
						$Comp = $CompatabilityLevel * 10
						$tsqlComp = "ALTER DATABASE $db SET COMPATIBILITY_LEVEL = $Comp"
						try {
							$db.ExecuteNonQuery($tsqlComp)
							$comResult = $Comp
						}
						catch {
							Write-Message -Level Warning -Message "Failed to change Compatibility Level" -ErrorRecord $_ -Target $instance
							$comResult = "Fail"
						}
					}
			}
			If ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
				$db.Refresh()

				[PSCustomObject]@{
					ComputerName          = $server.ComputerName
					InstanceName          = $server.ServiceName
					SqlInstance           = $server.DomainInstanceName
					Database              = $db.name
					OriginalCompatibility = $ogcompat.ToString().Replace('Version', '')
					CurrentCompatibility  = $db.CompatibilityLevel.ToString().Replace('Version', '')
					Compatibility         = $comResult
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Invoke-DbaDatabaseUpgrade
	}
}