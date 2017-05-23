function Export-DbaLogin {
	<#
		.SYNOPSIS
			Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

		.DESCRIPTION
			Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

		.PARAMETER SqlInstance
			The SQL Server instance name. SQL Server 2000 and above supported.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Login
			The login(s) to process - this list is autopopulated from the server. If unspecified, all logins will be processed.

		.PARAMETER ExcludeLogin
			The login(s) to exclude - this list is autopopulated from the server.

		.PARAMETER Database
			The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

		.PARAMETER FilePath
			The file to write to.

		.PARAMETER NoClobber
			Do not overwrite file

		.PARAMETER Append
			Append to file

		.PARAMETER NoJobs
			Does not export the Jobs

		.PARAMETER NoDatabases
			Does not export the databases

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent
			USE this switch to disable any kind of verbose messages

		.NOTES
			Tags: Export, Login
			Author: Chrissy LeMaire (@cl), netnerds.net
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Export-DbaLogin

		.EXAMPLE
			Export-DbaLogin -SqlInstance sql2005 -FilePath C:\temp\sql2005-logins.sql

			Exports SQL for the logins in server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

		.EXAMPLE
			Export-DbaLogin -SqlInstance sqlserver2014a -Exclude realcajun -SqlCredential $scred -FilePath C:\temp\logins.sql -Append

			Authenticates to sqlserver2014a using SQL Authentication. Exports all logins except for realcajun to C:\temp\logins.sql, and appends to the file if it exists. If not, the file will be created.

		.EXAMPLE
			Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -FilePath C:\temp\logins.sql

			Exports ONLY logins netnerds and realcajun from sqlsever2014a to the file  C:\temp\logins.sql

		.EXAMPLE
			Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -Database HR, Accounting

			Exports ONLY logins netnerds and realcajun from sqlsever2014a with the permissions on databases HR and Accounting
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[object[]]$Login,
		[object[]]$ExcludeLogin,
		[Alias("Databases")]
		[object[]]$Database,
		[Alias("OutFile", "Path", "FileName")]
		[string]$FilePath,
		[Alias("NoOverwrite")]
		[switch]$NoClobber,
		[switch]$Append,
		[switch]$NoDatabases,
		[switch]$NoJobs,
		[switch]$Silent
	)

	begin {

		if ($FilePath) {
			if ($FilePath -notlike "*\*") { $FilePath = ".\$filepath" }
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory

			if ($exists -eq $false) {
				Stop-Function -Message "Parent directory $directory does not exist"
			}

			Write-Message -Level Output -Message "Attempting to connect to SQL Servers.."
		}

		$sql = @()
	}
	process {
		if (Test-FunctionInterrupt) { return }

		try {
			Write-Message -Level Verbose -Message "Connecting to $sqlinstance"
			$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlcredential
		}
		catch {
			Stop-Function -Message "Failed to connect to $instance : $($_.Exception.Message)" -Continue -Target $instance -InnerErrorRecord $_
		}

		foreach ($sourcelogin in $server.logins) {
			$username = $sourcelogin.name

			if ($Login -and $Login -notcontains $username -or $ExcludeLogin -contains $username) { continue }

			if ($username.StartsWith("##") -or $username -eq 'sa') {
				Stop-Function -Message "Skipping $username" -Continue
			}

			$servername = $server

			$userbase = ($username.Split("\")[0]).ToLower()
			if ($servername -eq $userbase -or $username.StartsWith("NT ")) {
				If ($Pscmdlet.ShouldProcess("console", "Stating $username is skipped becaUSE it is a local machine name.")) {
					Stop-Function -Message "$username is skipped becaUSE it is a local machine name." -Continue
				}
			}

			If ($Pscmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $username")) {
				if ($FilePath) {
					Write-Message -Level Output -Message "Exporting $username"
				}
				
				$sql += "`r`nUSE master`n"
				# Getting some attributes
				$defaultdb = $sourcelogin.DefaultDatabase
				$language = $sourcelogin.Language

				if ($sourcelogin.PasswordPolicyEnforced -eq $false) {
					$checkpolicy = "OFF"
				}
				else {
					$checkpolicy = "ON"
				}

				if (!$sourcelogin.PasswordExpirationEnabled) {
					$checkexpiration = "OFF"
				}
				else {
					$checkexpiration = "ON"
				}

				# Attempt to script out SQL Login
				if ($sourcelogin.LoginType -eq "SqlLogin") {
					$sourceloginname = $sourcelogin.name

					switch ($server.versionMajor) {
						0 { $sql = "SELECT convert(varbinary(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceloginname'" }
						8 { $sql = "SELECT convert(varbinary(256),password) as hashedpass FROM dbo.syslogins WHERE name='$sourceloginname'" }
						9 { $sql = "SELECT convert(varbinary(256),password_hash) as hashedpass FROM sys.sql_logins where name='$sourceloginname'" }
						default {
							$sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') AS varbinary (256)), 1) AS nvarchar(max)) as hashedpass FROM sys.server_principals WHERE principal_id = $($sourcelogin.id)"
						}
					}

					try {
						$hashedpass = $server.ConnectionContext.ExecuteScalar($sql)
					}
					catch {
						$hashedpassdt = $server.databases['master'].ExecuteWithResults($sql)
						$hashedpass = $hashedpassdt.Tables[0].Rows[0].Item(0)
					}

					if ($hashedpass.gettype().name -ne "String") {
						$passtring = "0x"; $hashedpass | ForEach-Object { $passtring += ("{0:X}" -f $_).PadLeft(2, "0") }
						$hashedpass = $passtring
					}

					$sid = "0x"; $sourcelogin.sid | ForEach-Object { $sid += ("{0:X}" -f $_).PadLeft(2, "0") }
					$sql += "IF NOT EXISTS (SELECT loginname from master.dbo.syslogins where name = '$username')
CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$language]"
				}

				# Attempt to script out Windows User
				elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup") {
					$sql += "IF NOT EXISTS (SELECT loginname from master.dbo.syslogins where name = '$username')
CREATE LOGIN [$username] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultdb], DEFAULT_LANGUAGE = [$language]"
				}

				# This script does not currently support certificate mapped or asymmetric key users.
				else {
					Stop-Function -Message "$($sourcelogin.LoginType) logins not supported. $($sourcelogin.name) skipped." -Continue
				}

				if ($sourcelogin.IsDisabled) {
					$sql += "ALTER LOGIN [$username] DISABLE"
				}
				if ($sourcelogin.DenyWindowsLogin) {
					$sql += "DENY CONNECT SQL TO [$username]"
				}
			}

			# Server Roles: sysadmin, bulklogin, etc
			foreach ($role in $server.roles) {
				$rolename = $role.name

				# SMO changed over time
				try { $rolemembers = $role.EnumMemberNames() }
				catch { $rolemembers = $role.EnumServerRoleMembers() }

				if ($rolemembers -contains $username) {
					$sql += "ALTER SERVER ROLE [$rolename] ADD MEMBER [$username]"
				}
			}

			if ($NoJobs -eq $false) {
				$ownedjobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $username }

				foreach ($ownedjob in $ownedjobs) {
					$sql += "`n`rUSE msdb`n"
					$jobname = $ownedjob.name
					$sql += "EXEC msdb.dbo.sp_update_job @job_name=N'$jobname', @owner_login_name=N'$username'"
				}
			}

			if ($server.versionMajor -ge 9) {
				# These operations are only supported by SQL Server 2005 and above.
				# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.

				$perms = $server.EnumServerPermissions($username)
				$sql += "`n`rUSE master`n"
				foreach ($perm in $perms) {
					$permstate = $perm.permissionstate
					$permtype = $perm.PermissionType
					$grantor = $perm.grantor

					if ($permstate -eq "GrantWithGrant") {
						$grantwithgrant = "WITH GRANT OPTION"
						$permstate = "grant"
					}
					else {
						$grantwithgrant = $null
					}

					$sql += "$permstate $permtype TO [$username] $grantwithgrant AS [$grantor]"
				}

				# Credential mapping. Credential removal not currently supported for Syncs.
				$logincredentials = $server.credentials | Where-Object { $_.Identity -eq $sourcelogin.name }
				foreach ($credential in $logincredentials) {
					$credentialname = $credential.name
					$sql += "Print '$username is associated with the $credentialname credential'"
				}
			}

			if ($NoDatabases -eq $false) {
				$dbs = $sourcelogin.EnumDatabaseMappings()
				# Adding database mappings and securables
				foreach ($db in $dbs) {
					$dbname = $db.dbname
					if ($database -and $dbname -notin $database) {
						continue
					}
					$sourcedb = $server.databases[$dbname]
					$dbusername = $db.username

					$sql += "`r`nUSE [$dbname]`n"
					try {
						$sql = $server.databases[$dbname].users[$dbusername].script()
						$sql += $sql
					}
					catch {
						Write-Warning "User cannot be found in selected database"
					}

					# Skipping updating dbowner

					# Database Roles: db_owner, db_datareader, etc
					foreach ($role in $sourcedb.roles) {
						if ($role.EnumMembers() -contains $username) {
							$rolename = $role.name
							$sql += "ALTER ROLE [$rolename] ADD MEMBER [$username]"
						}
					}

					# Connect, Alter Any Assembly, etc
					$perms = $sourcedb.EnumDatabasePermissions($username)
					foreach ($perm in $perms) {
						$permstate = $perm.permissionstate
						$permtype = $perm.PermissionType
						$grantor = $perm.grantor

						if ($permstate -eq "GrantWithGrant") {
							$grantwithgrant = "WITH GRANT OPTION"
							$permstate = "grant"
						}
						else {
							$grantwithgrant = $null
						}

						$sql += "$permstate $permtype TO [$username] $grantwithgrant AS [$grantor]"
					}
				}
			}
		}
	}
	end {
		$sql = $sql | Where-Object { $_ -notlike "CREATE USER [dbo] FOR LOGIN * WITH DEFAULT_SCHEMA=[dbo]" }

		$sql = $sql -join "`r`nGO`r`n"

		if ($FilePath) {
			$sql | Out-File -Encoding UTF8 -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		}
		else {
			$sql
		}
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Export-SqlLogin
	}
}

