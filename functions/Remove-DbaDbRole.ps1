#ValidationTags#CodeStyle, Messaging, FlowControl, Pipeline#
function Remove-DbaDbRole {
    <#
    .SYNOPSIS
        Removes a database role from database(s) for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbRole removes role(s) from database(s) for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternate Windows or SQL Login Authentication. Accepts credential objects (Get-Credential).

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER Role
        The role(s) to process. If unspecified, all roles will be processed.

    .PARAMETER ExcludeRole
        The role(s) to exclude.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Database, Security, Login
        Author: Ben Miller (@DBAduck)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbRole

    .EXAMPLE
        PS C:\> Remove-DbaDbRole -SqlInstance localhost -Database dbname -Role "customrole1", "customrole2"

        Removes roles customrole1 and customrole2 from the database dbname on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbRole -SqlInstance localhost, sql2016 -Database db1, db2 -Role role1, role2, role3

        Removes role1,role2,role3 from db1 and db2 on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbRole -Database db1, db2 -Role role1

        Removes role1 from db1 and db2 on the servers in C:\servers.txt

    #>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstance[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[string[]]$Database,
		[string[]]$ExcludeDatabase,
		[string[]]$Role,
		[string[]]$ExcludeRole,
		[Alias('Silent')]
		[switch]$EnableException
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			} catch {
				Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			foreach ($item in $Database) {
				Write-Message -Level Verbose -Message "Check if database: $item on $instance is accessible or not"
				if ($server.Databases[$item].IsAccessible -eq $false) {
					Stop-Function -Message "Database: $item is not accessible. Check your permissions or database state." -Category ResourceUnavailable -ErrorRecord $_ -Target $instance -Continue
				}
			}
			
			$databases = $server.Databases | Where-Object {
				$_.IsAccessible -eq $true
			}
			
			if (Test-Bound -Parameter 'Database') {
				$databases = $databases | Where-Object {
					$_.Name -in $Database
				}
			}
			
			if (Test-Bound -Parameter 'ExcludeDatabase') {
				$databases = $databases | Where-Object {
					$_.Name -notin $ExcludeDatabase
				}
			}
			
			foreach ($db in $databases) {
				Write-Message -Level 'Verbose' -Message "Getting Database Roles for $db on $instance"
				
				$dbRoles = $db.Roles
				
				if (Test-Bound -Parameter 'Role') {
					$dbRoles = $dbRoles | Where-Object {
						$_.Name -in $Role
					}
				}
				
				if (Test-Bound -Parameter 'ExcludeRole') {
					$dbRoles = $dbRoles | Where-Object {
						$_.Name -notin $ExcludeRole
					}
				}
				
				# Trick to get a list without using the Collection
				$dbRoles = $dbRoles | Where-Object {
					$_.ID -gt 0
				}
				
				$dbRoles.Drop()
			}
		}
	}
	end {
		
	}
}