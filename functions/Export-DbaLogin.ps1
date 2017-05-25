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
			The login(s) to process - this list is autopopulated FROM the server. If unspecified, all logins will be processed.

		.PARAMETER ExcludeLogin
			The login(s) to exclude - this list is autopopulated FROM the server.

		.PARAMETER Database
			The database(s) to process - this list is autopopulated FROM the server. If unspecified, all databases will be processed.

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

			Exports ONLY logins netnerds and realcajun FROM sqlsever2014a to the file  C:\temp\logins.sql

		.EXAMPLE
			Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -Database HR, Accounting

			Exports ONLY logins netnerds and realcajun FROM sqlsever2014a with the permissions on databases HR and Accounting
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
				Write-Message -Level Warning -Message "Parent directory $directory does not exist"
			}
		}

		$outsql = @()
	}
	process {
		if (Test-FunctionInterrupt) { return }

		Write-Message -Level Verbose -Message "Connecting to $sqlinstance"
		$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlcredential

		foreach ($sourceLogin in $server.Logins) {
			$userName = $sourceLogin.name

			if ($Login -and $Login -notcontains $userName -or $ExcludeLogin -contains $userName) { continue }

			if ($userName.StartsWith("##") -or $userName -eq 'sa') {
				Write-Message -Level Warning -Message "Skipping $userName"
				continue
			}

			$serverName = $server

			$userBase = ($userName.Split("\")[0]).ToLower()
			if ($serverName -eq $userBase -or $userName.StartsWith("NT ")) {
				if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it is a local machine name.")) {
					Write-Message -Level Warning "$userName is skipped because it is a local machine name."
					continue
				}
			}

			if ($Pscmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $userName")) {
				if ($FilePath) {
					Write-Message -Level Output -Message "Exporting $userName"
				}
				
				$outsql += "`r`nUSE master`n"
				# Getting some attributes
				$defaultDb = $sourceLogin.DefaultDatabase
				$language = $sourceLogin.Language

				if ($sourceLogin.PasswordPolicyEnforced -eq $false) {
					$checkPolicy = "OFF"
				}
				else {
					$checkPolicy = "ON"
				}

				if (!$sourceLogin.PasswordExpirationEnabled) {
					$checkExpiration = "OFF"
				}
				else {
					$checkExpiration = "ON"
				}

				# Attempt to script out SQL Login
				if ($sourceLogin.LoginType -eq "SqlLogin") {
					$sourceLoginName = $sourceLogin.name

					switch ($server.versionMajor) {
						0 { $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceLoginName'" }
						8 { $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM dbo.syslogins WHERE name='$sourceLoginName'" }
						9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins WHERE name='$sourceLoginName'" }
						default {
							$sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass FROM sys.server_principals WHERE principal_id = $($sourceLogin.id)"
						}
					}

					try {
						$hashedPass = $server.ConnectionContext.ExecuteScalar($sql)
					}
					catch {
						$hashedPassDt = $server.Databases['master'].ExecuteWithResults($sql)
						$hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
					}

					if ($hashedPass.GetType().Name -ne "String") {
						$passString = "0x"; $hashedPass | ForEach-Object { $passString += ("{0:X}" -f $_).PadLeft(2, "0") }
						$hashedPass = $passString
					}

					$sid = "0x"; $sourceLogin.sid | ForEach-Object { $sid += ("{0:X}" -f $_).PadLeft(2, "0") }
					$outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] WITH PASSWORD = $hashedPass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkPolicy, CHECK_EXPIRATION = $checkExpiration, DEFAULT_LANGUAGE = [$language]"
				}
				# Attempt to script out Windows User
				elseif ($sourceLogin.LoginType -eq "WindowsUser" -or $sourceLogin.LoginType -eq "WindowsGroup") {
					$outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultDb], DEFAULT_LANGUAGE = [$language]"
				}
				# This script does not currently support certificate mapped or asymmetric key users.
				else {
					Write-Message -Level Warning -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.Name) skipped."
					continue
				}

				if ($sourceLogin.IsDisabled) {
					$outsql += "ALTER LOGIN [$userName] DISABLE"
				}

				if ($sourceLogin.DenyWindowsLogin) {
					$outsql += "DENY CONNECT SQL TO [$userName]"
				}
			}

			# Server Roles: sysadmin, bulklogin, etc
			foreach ($role in $server.Roles) {
				$roleName = $role.Name

				# SMO changed over time
				try { $roleMembers = $role.EnumMemberNames() }
				catch { $roleMembers = $role.EnumServerRoleMembers() }

				if ($roleMembers -contains $userName) {
					$outsql += "ALTER SERVER ROLE [$roleName] ADD MEMBER [$userName]"
				}
			}

			if ($NoJobs -eq $false) {
				$ownedJobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $userName }

				foreach ($ownedJob in $ownedJobs) {
					$outsql += "`n`rUSE msdb`n"
					$outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedJob', @owner_login_name=N'$userName'"
				}
			}

			if ($server.VersionMajor -ge 9) {
				# These operations are only supported by SQL Server 2005 and above.
				# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.

				$perms = $server.EnumServerPermissions($userName)
				$outsql += "`n`rUSE master`n"
				foreach ($perm in $perms) {
					$permState = $perm.permissionstate
					$permType = $perm.PermissionType
					$grantor = $perm.grantor

					if ($permState -eq "GrantWithGrant") {
						$grantWithGrant = "WITH GRANT OPTION"
						$permState = "GRANT"
					}
					else {
						$grantWithGrant = $null
					}

					$outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
				}

				# Credential mapping. Credential removal not currently supported for Syncs.
				$loginCredentials = $server.Credentials | Where-Object { $_.Identity -eq $sourceLogin.Name }
				foreach ($credential in $loginCredentials) {
					$credentialName = $credential.Name
					$outsql += "PRINT '$userName is associated with the $credentialName credential'"
				}
			}

			if ($NoDatabases -eq $false) {
				$dbs = $sourceLogin.EnumDatabaseMappings()
				# Adding database mappings and securables
				foreach ($db in $dbs) {
					$dbName = $db.dbname
					if ($database -and $dbName -notin $database) {
						continue
					}
					$sourceDb = $server.Databases[$dbName]
					$dbUserName = $db.username

					$outsql += "`r`nUSE [$dbName]`n"
					try {
						$sql = $server.Databases[$dbName].Users[$dbUserName].Script()
						$outsql += $sql
					}
					catch {
						Write-Message -Level Warning -Message "User cannot be found in selected database"
					}

					# Skipping updating dbowner

					# Database Roles: db_owner, db_datareader, etc
					foreach ($role in $sourceDb.Roles) {
						if ($role.EnumMembers() -contains $userName) {
							$roleName = $role.Name
							$outsql += "ALTER ROLE [$roleName] ADD MEMBER [$userName]"
						}
					}

					# Connect, Alter Any Assembly, etc
					$perms = $sourceDb.EnumDatabasePermissions($userName)
					foreach ($perm in $perms) {
						$permState = $perm.PermissionState
						$permType = $perm.PermissionType
						$grantor = $perm.Grantor

						if ($permState -eq "GrantWithGrant") {
							$grantWithGrant = "WITH GRANT OPTION"
							$permState = "GRANT"
						}
						else {
							$grantWithGrant = $null
						}

						$outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
					}
				}
			}
		}
	}
	end {
		$sql = $sql | Where-Object { $_ -notlike "CREATE USER [dbo] FOR LOGIN * WITH DEFAULT_SCHEMA=[dbo]" }

		$sql = $outsql -join "`r`nGO`r`n"

		if ($FilePath) {
			$sql | Out-File -Encoding UTF8 -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		}
		else {
			$sql
		}
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Export-SqlLogin
	}
}

