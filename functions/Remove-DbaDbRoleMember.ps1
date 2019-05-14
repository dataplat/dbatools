#ValidationTags#CodeStyle, Messaging, FlowControl, Pipeline#
function Remove-DbaDbRoleMember
{
    <#
    .SYNOPSIS
        Removes a Database User from a database role for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbRoleMember removes users in a database from a database role or roles for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternate Windows or SQL Login Authentication. Accepts credential objects (Get-Credential).

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Role
        The role(s) to process. 

	.PARAMETER User
		The user(s) to remove from the role(s) specified.
	
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
        https://dbatools.io/Remove-DbaDbRoleMember

    .EXAMPLE
        PS C:\> Remove-DbaDbRoleMember -SqlInstance localhost -Database mydb -Role db_owner -DatabaseUser user1

        Removes user1 from the role db_owner in the database mydb on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbRoleMember -SqlInstance localhost, sql2016 -Role SqlAgentOperatorRole -User user1 -Database msdb

        Removes user1 in servers localhost and sql2016 in the msdb database from the SqlAgentOperatorRole

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbRoleMember -Role SqlAgentOperatorRole -User user1 -Database msdb

        Removes user1 from the SqlAgentOperatorRole in the msdb database in every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Remove-DbaDbRoleMember -SqlInstance localhost -Role "db_datareader","db_datawriter" -User user1 -Database DEMODB

        Removes user1 in the database DEMODB on the server localhost from the roles db_datareader and db_datawriter

    #>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstance[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[string[]]$Database,
		[parameter(Mandatory)]
		[string[]]$Role,
		[parameter(Mandatory)]
		[string[]]$User,
		[Alias('Silent')]
		[switch]$EnableException
	)
	
	process
	{
		foreach ($instance in $SqlInstance)
		{
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch
			{
				Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			foreach ($item in $Database)
			{
				Write-Message -Level Verbose -Message "Check if database: $item on $instance is accessible or not"
				if ($server.Databases[$item].IsAccessible -eq $false)
				{
					Stop-Function -Message "Database: $item is not accessible. Check your permissions or database state." -Category ResourceUnavailable -ErrorRecord $_ -Target $instance -Continue
				}
			}
			
			$databases = $server.Databases | Where-Object { $_.IsAccessible -eq $true }
			
			if (Test-Bound -Parameter 'Database')
			{
				$databases = $databases | Where-Object { $_.Name -in $Database }
			}
			
			foreach ($db in $databases)
			{
				Write-Message -Level 'Verbose' -Message "Getting Database Roles for $db on $instance"
				
				$dbRoles = $db.Roles
				
				if (Test-Bound -Parameter 'Role')
				{
					$dbRoles = $dbRoles | Where-Object { $_.Name -in $Role }
				}
				
				foreach ($dbRole in $dbRoles)
				{
					Write-Message -Level 'Verbose' -Message "Getting Database Role Members for $dbRole in $db on $instance"
					
					$members = $dbRole.EnumMembers()
					
					foreach ($username in $User)
					{
						if ($members -contains $username)
						{
							Write-Message -Level 'Verbose' -Message "Removing User $username from $dbRole in $db on $instance"
							$dbRole.DropMember($username)
						}
					}
				} # end foreach($dbRole)
			} # end foreach($db)
		} # end foreach($server)
	}
	end
	{
		
	}
}