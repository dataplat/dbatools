Function Repair-DbaOrphanUser {
<#
.SYNOPSIS
Find orphan users with existing login and remap.

.DESCRIPTION
An orphan user is defined by a user that does not have their matching login. (Login property = "")

If the matching login exists it must be:
	Enabled
	Not a system object
	Not locked
	Have the same name that user

You can drop users that does not have their matching login by especifing the parameter -RemoveNotExisting This will be made by calling Remove-DbaOrphanUser function.


.PARAMETER SqlInstance
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Users
List of users to repair

.PARAMETER RemoveNotExisting
If passed, all users that not have their matching login will be dropped from database

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.EXAMPLE
Repair-DbaOrphanUser -SqlInstance sql2005

Will find and repair all orphan users of all databases present on server 'sql2005'

.EXAMPLE
Repair-DbaOrphanUser -SqlInstance sqlserver2014a -SqlCredential $cred

Will find and repair all orphan users of all databases present on server 'sqlserver2014a'. Will be verified using SQL credentials.

.EXAMPLE
Repair-DbaOrphanUser -SqlInstance sqlserver2014a -Database db1, db2

Will find and repair all orphan users on both db1 and db2 databases

.EXAMPLE
Repair-DbaOrphanUser -SqlInstance sqlserver2014a -Database db1 -Users OrphanUser

Will find and repair user 'OrphanUser' on 'db1' database

.EXAMPLE
Repair-DbaOrphanUser -SqlInstance sqlserver2014a -Users OrphanUser

Will find and repair user 'OrphanUser' on all databases

.EXAMPLE
Repair-DbaOrphanUser -SqlInstance sqlserver2014a -RemoveNotExisting

Will find all orphan users of all databases present on server 'sqlserver2014a'
Will also remove all users that does not have their matching login by calling Remove-DbaOrphanUser function

.NOTES
Tags: Orphan
Original Author: Claudio Silva (@ClaudioESSilva)
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Repair-DbaOrphanUser
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[Alias("Databases")]
		[object[]]$Database,
		[parameter(Mandatory = $false, ValueFromPipeline = $true)]
		[object[]]$Users,
		[switch]$RemoveNotExisting,
		[switch]$Silent
	)

	process {
        $start = [System.Diagnostics.Stopwatch]::StartNew()
		foreach ($instance in $SqlInstance) {
			
			try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Write-Message -Level Warning -Message "Failed to connect to: $SqlInstance"
				continue
			}

			if ($Database.Count -eq 0) {

				$DatabaseCollection = $server.Databases | Where-Object { $_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true }
			}
			else {
				if ($pipedatabase.Length -gt 0) {
					$Source = $pipedatabase[0].parent.name
					$DatabaseCollection = $pipedatabase.name
				}
				else {
					$DatabaseCollection = $server.Databases | Where-Object { $_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true -and ($Database -contains $_.Name) }
				}
			}

			if ($DatabaseCollection.Count -gt 0) {
				foreach ($db in $DatabaseCollection) {
					try {
						#if SQL 2012 or higher only validate databases with ContainmentType = NONE
						if ($server.versionMajor -gt 10) {
							if ($db.ContainmentType -ne [Microsoft.SqlServer.Management.Smo.ContainmentType]::None) {
								Write-Message -Level Warning -Message "Database '$db' is a contained database. Contained databases can't have orphaned users. Skipping validation."
								Continue
							}
						}

						Write-Message -Level Verbose -Message "Validating users on database '$db'"

						if ($Users.Count -eq 0) {
							#the third validation will remove from list sql users without login. The rule here is Sid with length higher than 16
							$Users = $db.Users | Where-Object { $_.Login -eq "" -and ($_.ID -gt 4) -and ($_.Sid.Length -gt 16 -and $_.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin) -eq $false }
						}
						else {
							if ($pipedatabase.Length -gt 0) {
								$Source = $pipedatabase[3].parent.name
								$Users = $pipedatabase.name
							}
							else {
								#the fourth validation will remove from list sql users without login. The rule here is Sid with length higher than 16
								$Users = $db.Users | Where-Object { $_.Login -eq "" -and ($_.ID -gt 4) -and ($Users -contains $_.Name) -and (($_.Sid.Length -gt 16 -and $_.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin) -eq $false) }
							}
						}

						if ($Users.Count -gt 0) {
							Write-Message -Level Verbose -Message "Orphan users found"
							$UsersToRemove = @()
							foreach ($User in $Users) {
								$ExistLogin = $server.logins | Where-Object {
									$_.Isdisabled -eq $False -and
									$_.IsSystemObject -eq $False -and
									$_.IsLocked -eq $False -and
									$_.Name -eq $User.Name
								}

								if ($ExistLogin) {
									if ($server.versionMajor -gt 8) {
										$query = "ALTER USER " + $User + " WITH LOGIN = " + $User
									}
									else {
										$query = "exec sp_change_users_login 'update_one', '$User'"
									}

									if ($Pscmdlet.ShouldProcess($db.Name, "Mapping user '$($User.Name)'")) {
										$server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
										Write-Message -Level Verbose -Message "`r`nUser '$($User.Name)' mapped with their login"

										[PSCustomObject]@{
															SqlInstance = $server.name
															DatabaseName = $db.Name
															User = $User.Name
															Status = "Success"
														}
									}
								}
								else {
									if ($RemoveNotExisting -eq $true) {
										#add user to collection
										$UsersToRemove += $User
									}
									else {
										Write-Message -Level Verbose -Message "Orphan user $($User.Name) does not have matching login."
										[PSCustomObject]@{
															SqlInstance = $server.name
															DatabaseName = $db.Name
															User = $User.Name
															Status = "No matching login"
														}
									}
								}
							}

							#With the colelction complete invoke remove.
							if ($RemoveNotExisting -eq $true) {
								if ($Pscmdlet.ShouldProcess($db.Name, "Remove-DbaOrphanUser")) {
									Write-Message -Level Verbose -Message "Calling 'Remove-DbaOrphanUser'"
									Remove-DbaOrphanUser -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Database $db.Name -Users $UsersToRemove
								}
							}
						}
						else {
							Write-Message -Level Verbose -Message "No orphan users found on database '$db'"
						}
						#reset collection
						$Users = $null
					}
					catch {
						Stop-Function -Message $_ -Continue
					}
				}
			}
			else {
				Write-Message -Level Verbose -Message "There are no databases to analyse."
			}
		}
	}
	end {
		$totaltime = ($start.Elapsed)
		Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime"

		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Repair-SqlOrphanUser
	}
}
