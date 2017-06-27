function Copy-DbaLogin {
	<#
		.SYNOPSIS
			Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and above.

		.DESCRIPTION
			SQL Server 2000: Migrates logins with SIDs, passwords, server roles and database roles.

			SQL Server 2005 & above: Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc.)

			The login hash algorithm changed in SQL Server 2012, and is not backwards compatible with previous SQL versions. This means that while SQL Server 2000 logins can be migrated to SQL Server 2012, logins created in SQL Server 2012 can only be migrated to SQL Server 2012 and above.

		.PARAMETER Source
			Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Login
			The login(s) to process - this list is autopopulated from the server. If unspecified, all logins will be processed.

		.PARAMETER ExcludeLogin
			The login(s) to exclude - this list is autopopulated from the server

		.PARAMETER SyncOnly
			Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped.
			Credential removal not currently supported for Syncs. TODO: Application role sync

		.PARAMETER SyncSaName
			Want to sync up the name of the sa account on the source and destination? Use this switch.

		.PARAMETER OutFile
			Calls Export-SqlLogin and exports all logins to a T-SQL formatted file. This does not perform a copy, so no destination is required.

		.PARAMETER PipeLogin
			Takes the parameters required from a login object that has been piped ot the command

		.PARAMETER LoginRenameHashtable
			Takes a hash table that will pass to Rename-DbaLogin and update the login and mappings once the copy is completed.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Force drops and recreates logins. Logins that own jobs cannot be dropped at this time.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Login
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaLogin

		.EXAMPLE
			Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force

			Copies all logins from source server to destination server. If a SQL login on source exists on the destination, the destination login will be dropped and recreated.

		.EXAMPLE
			Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

			Authenticates to SQL Servers using SQL Authentication.

			Copies all logins except for realcajun. If a login already exists on the destination, the login will not be migrated.

		.EXAMPLE
			Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds -force

			Copies ONLY logins netnerds and realcajun. If login realcajun or netnerds exists on the destination, they will be dropped and recreated.

		.EXAMPLE
			Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -SyncOnly

			Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped.

		.EXAMPLE
			Copy-DbaLogin -LoginRenameHashtable @{ "OldUser" ="newlogin" } -Source $Sql01 -Destination Localhost -SourceSqlCredential $sqlcred

			Copys down OldUser and then renames it to newlogin.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$Login,
		[object[]]$ExcludeLogin,
		[switch]$SyncOnly,
		[parameter(ParameterSetName = "Live")]
		[switch]$SyncSaName,
		[parameter(ParameterSetName = "File", Mandatory = $true)]
		[string]$OutFile,
		[object]$PipeLogin,
		[hashtable]$LoginRenameHashtable,
		[switch]$Force,
		[switch]$Silent
	)

	begin {
		function Copy-Login {
			foreach ($sourceLogin in $sourceServer.Logins) {

				$userName = $sourceLogin.name

				$copyLoginStatus = [pscustomobject]@{
					SourceServer      = $sourceServer.Name
					DestinationServer = $destServer.Name
					SourceLogin       = $userName
					DestinationLogin  = $userName
					Type              = $sourceLogin.LoginType
					Status            = $null
					Notes             = $null
					DateTime          = [DbaDateTime](Get-Date)
				}

				if ($Login -and $Login -notcontains $userName -or $ExcludeLogin -contains $userName) { continue }

				if ($sourceLogin.id -eq 1) { continue }

				if ($userName.StartsWith("##") -or $userName -eq 'sa') {
					Write-Message -Level Verbose -Message "Skipping $userName"
					continue
				}

				$serverName = Resolve-NetBiosName $sourceServer

				$currentLogin = $sourceServer.ConnectionContext.truelogin

				if ($currentLogin -eq $userName -and $force) {
					if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it is performing the migration.")) {
						Write-Message -Level Warning -Message "Cannot drop login performing the migration. Skipping"
					}

					$copyLoginStatus.Status = "Skipped"
					$copyLoginStatus
					continue
				}

				if (($destServer.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($sourceLogin.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin)) {
					Write-Message -Level Warning -Message "$Destination does not have Mixed Mode enabled. [$userName] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
				}

				$userBase = ($userName.Split("\")[0]).ToLower()

				if ($serverName -eq $userBase -or $userName.StartsWith("NT ")) {
					if ($sourceServer.NetName -ne $destServer.NetName) {
						if ($Pscmdlet.ShouldProcess("console", "Stating $userName was skipped because it is a local machine name.")) {
							Write-Message -Level Warning -Message "$userName was skipped because it is a local machine name."
						}

						$copyLoginStatus.Status = "Skipped"
						$copyLoginStatus
						continue
					}
					else {
						if ($Pscmdlet.ShouldProcess("console", "Stating local login $userName since the source and destination server reside on the same machine.")) {
							Write-Message -Level Verbose -Message "Copying local login $userName since the source and destination server reside on the same machine."
						}
					}
				}

				if (($Login = $destServer.Logins.Item($userName)) -ne $null -and !$force) {
					if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it exists at destination.")) {
						Write-Message -Level Warning -Message "$userName already exists in destination. Use -Force to drop and recreate."
					}

					$copyLoginStatus.Status = "Skipped"
					$copyLoginStatus
					continue
				}

				if ($Login -ne $null -and $force) {
					if ($userName -eq $destServer.ServiceAccount) {
						Write-Message -Level Warning -Message "$userName is the destination service account. Skipping drop."

						$copyLoginStatus.Status = "Skipped"
						$copyLoginStatus
						continue
					}

					if ($Pscmdlet.ShouldProcess($destination, "Dropping $userName")) {

						# Kill connections, delete user
						Write-Message -Level Verbose -Message "Attempting to migrate $userName"
						Write-Message -Level Verbose -Message "Force was specified. Attempting to drop $userName on $destination"

						try {
							$ownedDbs = $destServer.Databases | Where-Object Owner -eq $userName

							foreach ($ownedDb in $ownedDbs) {
								Write-Message -Level Verbose -Message "Changing database owner for $($ownedDb.name) from $userName to sa"
								$ownedDb.SetOwner('sa')
								$ownedDb.Alter()
							}

							$ownedJobs = $destServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $userName

							foreach ($ownedJob in $ownedJobs) {
								Write-Message -Level Verbose -Message "Changing job owner for $($ownedJob.name) from $userName to sa"
								$ownedJob.Set_OwnerLoginName('sa')
								$ownedJob.Alter()
							}

							$login.Disable()
							$destServer.EnumProcesses() | Where-Object Login -eq $userName | ForEach-Object {
								$destServer.KillProcess($_.spid)
							}
							$login.Drop()

							Write-Message -Level Verbose -Message "Successfully dropped $userName on $destination"
						}
						catch {
							$copyLoginStatus.Status = "Failed"
							$copyLoginStatus

							Stop-Function -Message "Could not drop $userName" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
						}
					}
				}

				if ($Pscmdlet.ShouldProcess($destination, "Adding SQL login $userName")) {

					Write-Message -Level Verbose -Message "Attempting to add $userName to $destination"
					$destLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($destServer, $userName)

					Write-Message -Level Verbose -Message "Setting $userName SID to source username SID"
					$destLogin.Set_Sid($sourceLogin.Get_Sid())

					$defaultDb = $sourceLogin.DefaultDatabase

					Write-Message -Level Verbose -Message "Setting login language to $($sourceLogin.Language)"
					$destLogin.Language = $sourceLogin.Language

					if ($destServer.databases[$defaultDb] -eq $null) {
						Write-Message -Level Warning -Message "$defaultDb does not exist on destination. Setting defaultdb to master."
						$defaultDb = "master"
					}

					Write-Message -Level Verbose -Message "Set $userName defaultdb to $defaultDb"
					$destLogin.DefaultDatabase = $defaultDb

					$checkexpiration = "ON"; $checkpolicy = "ON"

					if ($sourceLogin.PasswordPolicyEnforced -eq $false) { $checkpolicy = "OFF" }

					if (!$sourceLogin.PasswordExpirationEnabled) { $checkexpiration = "OFF" }

					$destLogin.PasswordPolicyEnforced = $sourceLogin.PasswordPolicyEnforced
					$destLogin.PasswordExpirationEnabled = $sourceLogin.PasswordExpirationEnabled

					# Attempt to add SQL Login User
					if ($sourceLogin.LoginType -eq "SqlLogin") {
						$destLogin.LoginType = "SqlLogin"
						$sourceLoginname = $sourceLogin.name

						switch ($sourceServer.versionMajor) {
							0 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceLoginname'" }
							8 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM dbo.syslogins WHERE name='$sourceLoginname'" }
							9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins where name='$sourceLoginname'" }
							default {
								$sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash')
						AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass FROM sys.server_principals
						WHERE principal_id = $($sourceLogin.id)"
							}
						}

						try {
							$hashedPass = $sourceServer.ConnectionContext.ExecuteScalar($sql)
						}
						catch {
							$hashedPassDt = $sourceServer.Databases['master'].ExecuteWithResults($sql)
							$hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
						}

						if ($hashedPass.GetType().Name -ne "String") {
							$passString = "0x"; $hashedPass | ForEach-Object { $passString += ("{0:X}" -f $_).PadLeft(2, "0") }
							$hashedPass = $passString
						}

						try {
							$destLogin.Create($hashedPass, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
							$destLogin.Refresh()
							Write-Message -Level Verbose -Message "Successfully added $userName to $destination"

							$copyLoginStatus.Status = "Successful"
							$copyLoginStatus

						}
						catch {
							try {
								$sid = "0x"; $sourceLogin.sid | ForEach-Object { $sid += ("{0:X}" -f $_).PadLeft(2, "0") }
								$sql = "CREATE LOGIN [$userName] WITH PASSWORD = $hashedPass HASHED, SID = $sid,
												DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkpolicy,
												CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$($sourceLogin.Language)]"

								$null = $destServer.ConnectionContext.ExecuteNonQuery($sql)

								$destLogin = $destServer.logins[$userName]
								Write-Message -Level Verbose -Message "Successfully added $userName to $destination"

								$copyLoginStatus.Status = "Successful"
								$copyLoginStatus

							}
							catch {
								$copyLoginStatus.Status = "Failed"
								$copyLoginStatus

								Stop-Function -Message "Failed to add $userName to $destination" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
							}
						}
					}
					# Attempt to add Windows User
					elseif ($sourceLogin.LoginType -eq "WindowsUser" -or $sourceLogin.LoginType -eq "WindowsGroup") {
						Write-Message -Level Verbose -Message "Adding as login type $($sourceLogin.LoginType)"
						$destLogin.LoginType = $sourceLogin.LoginType

						Write-Message -Level Verbose -Message "Setting language as $($sourceLogin.Language)"
						$destLogin.Language = $sourceLogin.Language

						try {
							$destLogin.Create()
							$destLogin.Refresh()
							Write-Message -Level Verbose -Message "Successfully added $userName to $destination"

							$copyLoginStatus.Status = "Successful"
							$copyLoginStatus

						}
						catch {
							$copyLoginStatus.Status = "Failed"
							$copyLoginStatus

							Stop-Function -Message "Failed to add $userName to $destination" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
						}
					}
					# This script does not currently support certificate mapped or asymmetric key users.
					else {
						Write-Message -Level Warning -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.name) skipped."

						$copyLoginStatus.Status = "Skipped"
						$copyLoginStatus

						continue
					}

					if ($sourceLogin.IsDisabled) {
						try {
							$destLogin.Disable()
						}
						catch {
							$copyLoginStatus.Status = "Successful - but could not disable on destination"
							$copyLoginStatus

							Stop-Function -Message "$userName disabled on source, could not be disabled on $destination" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
						}
					}
					if ($sourceLogin.DenyWindowsLogin) {
						try {
							$destLogin.DenyWindowsLogin = $true
						}
						catch {
							$copyLoginStatus.Status = "Successful - but could not deny login on destination"
							$copyLoginStatus

							Stop-Function -Message "$userName denied login on source, could not be denied login on $destination" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
						}
					}
				}
				if ($Pscmdlet.ShouldProcess($destination, "Updating SQL login $userName permissions")) {
					Update-SqlPermissions -sourceserver $sourceServer -sourcelogin $sourceLogin -destserver $destServer -destlogin $destLogin
				}

				if ($LoginRenameHashtable.Keys -contains $userName) {
					$NewLogin = $LoginRenameHashtable[$userName]

					if ($Pscmdlet.ShouldProcess($destination, "Renaming SQL Login $userName to $NewLogin")) {
						try {
							Rename-DbaLogin -SqlInstance $destServer -Login $userName -NewLogin $NewLogin

							$copyLoginStatus.DestinationLogin = $NewLogin
							$copyLoginStatus.Status = "Successful"
							$copyLoginStatus

						}
						catch {
							$copyLoginStatus.DestinationLogin = $NewLogin
							$copyLoginStatus.Status = "Failed to rename"
							$copyLoginStatus

							Stop-Function -Message "Issue renaming $userName to $NewLogin" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
						}
					}
				}
			} #end for each $sourceLogin
		} #end function Copy-Login

		Write-Message -Level Verbose -Message "Attempting to connect to SQL Servers.."
		$sourceServer = Connect-SqlInstance -RegularUser -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$source = $sourceServer.DomainInstanceName

		if ($Destination) {
			$destServer = Connect-SqlInstance -RegularUser -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
			$Destination = $destServer.DomainInstanceName

			$sourceVersionMajor = $sourceServer.VersionMajor
			$destVersionMajor = $destServer.VersionMajor
			if ($sourceVersionMajor -gt 10 -and $destVersionMajor -lt 11) {
				Stop-Function -Message "Login migration from version $sourceVersionMajor to $destVersionMajor is not supported." -Category InvalidOperation -InnerErrorRecord $_ -Target $sourceServer
			}

			if ($sourceVersionMajor -lt 8 -or $destVersionMajor -lt 8) {
				Stop-Function -Message "SQL Server 7 and below are not supported." -Category InvalidOperation -InnerErrorRecord $_ -Target $sourceServer
			}
		}

		$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
		$started = Get-Date

		if ($Pscmdlet.ShouldProcess("console", "Showing time started message")) {
			Write-Message -Level Verbose -Message "Migration started: $started"
		}

		if ($Login) {
			$LoginParms += @{ 'Logins' = $Login }
		}
		elseif ($ExcludeLogin) {
			$LoginParms += @{ 'Exclude' = $ExcludeLogin }
		}
		else {
			$Login = $sourceServer.Logins.Name
		}

		return $serverParms
	}
	process {
		if ($PipeLogin.Length -gt 0) {
			$Source = $PipeLogin[0].Parent.Name
			$Login = $PipeLogin.Name
		}

		if ($SyncOnly) {
			Sync-DbaSqlLoginPermission -Source $Source -Destination $Destination $loginparms
			return
		}

		if ($OutFile) {
			Export-SqlLogin -SqlInstance $source -FilePath $OutFile $loginparms
			return
		}

		if ($Pscmdlet.ShouldProcess("console", "Showing migration attempt message")) {
			Write-Message -Level Verbose -Message "Attempting Login Migration"
		}

		Copy-Login -sourceserver $sourceServer -destserver $destServer -Login $Login -Exclude $ExcludeLogin -Force $force

		$sa = $sourceServer.Logins | Where-Object id -eq 1
		$destSa = $destServer.Logins | Where-Object id -eq 1
		$saName = $sa.Name

		if ($saName -ne $destSa.name -and $SyncSaName) {
			Write-Message -Level Verbose -Message "Changing sa username to match source ($saName)"

			if ($Pscmdlet.ShouldProcess($destination, "Changing sa username to match source ($saName)")) {
				$destSa.Rename($saName)
				$destSa.Alter()
			}
		}
	}
	end {
		if ($Pscmdlet.ShouldProcess("console", "Showing time elapsed message")) {
			Write-Message -Level Verbose -Message "Login migration completed: $(Get-Date)"
			$totalTime = ($elapsed.Elapsed.toString().Split(".")[0])
			$sourceServer.ConnectionContext.Disconnect()

			if ($Destination.length -gt 0) {
				$destServer.ConnectionContext.Disconnect()
			}

			Write-Message -Level Verbose -Message "Total elapsed time: $totalTime"
		}
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlLogin
	}
}