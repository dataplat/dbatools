function Test-DbaValidLogin {
	<#
		.SYNOPSIS
			Test-DbaValidLogin finds any logins on SQL instance that are AD logins with either disabled AD user accounts or ones that no longer exist

		.DESCRIPTION
			The purpose of this function is to find SQL Server logins that are used by active directory users that are either disabled or removed from the domain. It allows you to keep your logins accurate and up to date by removing accounts that are no longer needed.

		.PARAMETER SqlInstance
			The SQL Server instance you're checking logins on. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Login
			Specifies a list of logins to include in the results. Options for this list are auto-populated from the server.

		.PARAMETER ExcludeLogin
			Specifies a list of logins to exclude from the results. Options for this list are auto-populated from the server.

		.PARAMETER FilterBy
			Specifies the object types to return. By default, both Logins and Groups are returned. Valid options for this parameter are 'GroupsOnly' and 'LoginsOnly'.

		.PARAMETER IgnoreDomains
			Specifies a list of Active Directory domains to ignore. By default, all domains in the forest as well as all trusted domains are traversed.
			
		.PARAMETER Detailed
			If this switch is enabled, more detailed results are returned. This includes the Active Directory account type and whether the login on SQL Server is enabled or disabled.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES
			Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/
			Author: Chrissy LeMaire (@cl), netnerds.net

			dWebsite: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaValidLogin

		.EXAMPLE
			Test-DbaValidLogin -SqlInstance Dev01

			Tests all logins in the current Active Directory domain that are either disabled or do not exist on the SQL Server instance Dev01

		.EXAMPLE
			Test-DbaValidLogin -SqlInstance Dev01 -FilterBy GroupsOnly -Detailed

			Tests all Active Directory groups that have logins on Dev01, returning a detailed view.

		.EXAMPLE
			Test-DbaValidLogin -SqlInstance Dev01 -ExcludeDomains subdomain

			Tests all logins excluding any that are from the subdomain Domain

	#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]
		$SqlCredential,
		[object[]]$Login,
		[object[]]$ExcludeLogin,
		[ValidateSet("LoginsOnly", "GroupsOnly")]
		[string]$FilterBy = "None",
		[string[]]$IgnoreDomains,
		[switch]$Detailed,
		[switch]$Silent
	)

	begin {
		if ($IgnoreDomains) {
			$IgnoreDomainsNormalized = $IgnoreDomains.toUpper()
			Write-Message -Message ("Excluding logins for domains " + ($IgnoreDomains -join ',')) -Level Verbose
		}
		if ($Detailed) {
			Write-Message -Message "Detailed is deprecated and will be removed in dbatools 1.0." -Once "DetailedDeprecation" -Level Warning
		}

		$MappingRaw = @{
			'SCRIPT'                                 = 1
			'ACCOUNTDISABLE'                         = 2
			'HOMEDIR_REQUIRED'                       = 8
			'LOCKOUT'                                = 16
			'PASSWD_NOTREQD'                         = 32
			'PASSWD_CANT_CHANGE'                     = 64
			'ENCRYPTED_TEXT_PASSWORD_ALLOWED'        = 128
			'TEMP_DUPLICATE_ACCOUNT'                 = 256
			'NORMAL_ACCOUNT'                         = 512
			'INTERDOMAIN_TRUST_ACCOUNT'              = 2048
			'WORKSTATION_TRUST_ACCOUNT'              = 4096
			'SERVER_TRUST_ACCOUNT'                   = 8192
			'DONT_EXPIRE_PASSWD'                     = 65536
			'MNS_LOGON_ACCOUNT'                      = 131072
			'SMARTCARD_REQUIRED'                     = 262144
			'TRUSTED_FOR_DELEGATION'                 = 524288
			'NOT_DELEGATED'                          = 1048576
			'USE_DES_KEY_ONLY'                       = 2097152
			'DONT_REQUIRE_PREAUTH'                   = 4194304
			'PASSWORD_EXPIRED'                       = 8388608
			'TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION' = 16777216
			'NO_AUTH_DATA_REQUIRED'                  = 33554432
			'PARTIAL_SECRETS_ACCOUNT'                = 67108864
		}
	}
	process {
		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
				Write-Message -Message "Connected to: $instance." -Level Verbose
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}


			# we can only validate AD logins
			$allwindowsloginsgroups = $server.Logins | Where-Object { $_.LoginType -in ('WindowsUser', 'WindowsGroup') }

			# we cannot validate local users
			$allwindowsloginsgroups = $allwindowsloginsgroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($server.NetName) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
			if ($Login) {
				$allwindowsloginsgroups = $allwindowsloginsgroups | Where-Object { $Login -contains $_.Name }
			}
			if ($ExcludeLogin) {
				$allwindowsloginsgroups = $allwindowsloginsgroups | Where-Object { $ExcludeLogin -notcontains $_.Name }
			}
			switch ($FilterBy) {
				"LoginsOnly" {
					Write-Message -Message "Search restricted to logins." -Level Verbose
					$windowslogins = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsUser' }
				}
				"GroupsOnly" {
					Write-Message -Message "Search restricted to groups." -Level Verbose
					$windowsGroups = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsGroup' }
				}
				"None" {
					Write-Message -Message "Search both logins and groups." -Level Verbose
					$windowslogins = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsUser' }
					$windowsGroups = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsGroup' }
				}
			}
			foreach ($login in $windowslogins) {
				$adlogin = $login.Name
				$loginsid = $login.Sid -join ''
				$domain, $username = $adlogin.Split("\")
				if ($domain.toUpper() -in $IgnoreDomainsNormalized) {
					Write-Message -Message "Skipping Login $adlogin." -Level Verbose
					continue
				}
				Write-Message -Message "Parsing Login $adlogin." -Level Verbose
				$exists = $false
				try {
					$u = Get-DbaADObject -ADObject $adlogin -Type User -Silent
					$founduser = $u.GetUnderlyingObject()
					$foundsid = $founduser.objectSid.Value -join ''
					if ($founduser) {
						$exists = $true
					}
					if ($foundsid -ne $loginsid) {
						Write-Message -Message "SID mismatch detected for $adlogin." -Level Warning
						Write-Message -Message "SID mismatch detected for $adlogin (MSSQL: $loginsid, AD: $foundsid)." -Level Debug
						$exists = $false
					}
				}
				catch {
					Write-Message -Message "AD Searcher Error for $username." -Level Warning
				}
				
				$UAC = $founduser.Properties.userAccountControl
				
				$additionalProps = @{
					AccountNotDelegated               = $null
					AllowReversiblePasswordEncryption = $null
					CannotChangePassword              = $null
					PasswordExpired                   = $null
					Lockedout                         = $null
					Enabled                           = $null
					PasswordNeverExpires              = $null
					PasswordNotRequired               = $null
					SmartcardLogonRequired            = $null
					TrustedForDelegation              = $null
				}
				if ($UAC) {
					$additionalProps = @{
						AccountNotDelegated               = [bool]($UAC.Value -band $MappingRaw['NOT_DELEGATED'])
						AllowReversiblePasswordEncryption = [bool]($UAC.Value -band $MappingRaw['ENCRYPTED_TEXT_PASSWORD_ALLOWED'])
						CannotChangePassword              = [bool]($UAC.Value -band $MappingRaw['PASSWD_CANT_CHANGE'])
						PasswordExpired                   = [bool]($UAC.Value -band $MappingRaw['PASSWORD_EXPIRED'])
						Lockedout                         = [bool]($UAC.Value -band $MappingRaw['LOCKOUT'])
						Enabled                           = !($UAC.Value -band $MappingRaw['ACCOUNTDISABLE'])
						PasswordNeverExpires              = [bool]($UAC.Value -band $MappingRaw['DONT_EXPIRE_PASSWD'])
						PasswordNotRequired               = [bool]($UAC.Value -band $MappingRaw['PASSWD_NOTREQD'])
						SmartcardLogonRequired            = [bool]($UAC.Value -band $MappingRaw['SMARTCARD_REQUIRED'])
						TrustedForDelegation              = [bool]($UAC.Value -band $MappingRaw['TRUSTED_FOR_DELEGATION'])
						UserAccountControl                = $UAC.Value
					}
				}
				$rtn = [PSCustomObject]@{
					Server                            = $server.DomainInstanceName
					Domain                            = $domain
					Login                             = $username
					Type                              = "User"
					Found                             = $exists
					DisabledInSQLServer               = $login.IsDisabled
					AccountNotDelegated               = $additionalProps.AccountNotDelegated
					AllowReversiblePasswordEncryption = $additionalProps.AllowReversiblePasswordEncryption
					CannotChangePassword              = $additionalProps.CannotChangePassword
					PasswordExpired                   = $additionalProps.PasswordExpired
					Lockedout                         = $additionalProps.Lockedout
					Enabled                           = $additionalProps.Enabled
					PasswordNeverExpires              = $additionalProps.PasswordNeverExpires
					PasswordNotRequired               = $additionalProps.PasswordNotRequired
					SmartcardLogonRequired            = $additionalProps.SmartcardLogonRequired
					TrustedForDelegation              = $additionalProps.TrustedForDelegation
					UserAccountControl                = $additionalProps.UserAccountControl
				}
				if ($Detailed) {
					Select-DefaultView -InputObject $rtn -ExcludeProperty UserAccountControl
				}
				else {
					Select-DefaultView -InputObject $rtn -ExcludeProperty UserAccountControl, AccountNotDelegated, AllowReversiblePasswordEncryption, CannotChangePassword, PasswordNeverExpires, SmartcardLogonRequired, TrustedForDelegation
				}

			}

			foreach ($login in $windowsGroups) {
				$adlogin = $login.Name
				$loginsid = $login.Sid -join ''
				$domain, $groupname = $adlogin.Split("\")
				if ($domain.toUpper() -in $IgnoreDomainsNormalized) {
					Write-Message -Message "Skipping Login $adlogin." -Level Verbose
					continue
				}
				Write-Message -Message "Parsing Login $adlogin on $server." -Level Verbose
				$exists = $false
				if ($true) {
					$u = Get-DbaADObject -ADObject $adlogin -Type Group -Silent
					$founduser = $u.GetUnderlyingObject()
					if ($founduser) {
						$exists = $true
					}
					$foundsid = $founduser.objectSid.Value -join ''
					if ($foundsid -ne $loginsid) {
						Write-Message -Message "SID mismatch detected for $adlogin." -Level Warning
						Write-Message -Message "SID mismatch detected for $adlogin (MSSQL: $loginsid, AD: $foundsid)." -Level Debug
						$exists = $false
					}
				}
				else {
					Write-Warning -Message "AD Searcher Error for $groupname on $server" -Level Warning
				}
				$rtn = [PSCustomObject]@{
					Server                            = $server.DomainInstanceName
					Domain                            = $domain
					Login                             = $groupname
					Type                              = "Group"
					Found                             = $exists
					DisabledInSQLServer               = $login.IsDisabled
					AccountNotDelegated               = $null
					AllowReversiblePasswordEncryption = $null
					CannotChangePassword              = $null
					PasswordExpired                   = $null
					Lockedout                         = $null
					Enabled                           = $null
					PasswordNeverExpires              = $null
					PasswordNotRequired               = $null
					SmartcardLogonRequired            = $null
					TrustedForDelegation              = $null
					UserAccountControl                = $null
				}
				if ($Detailed) {
					Select-DefaultView -InputObject $rtn -ExcludeProperty UserAccountControl
				}
				else {
					Select-DefaultView -InputObject $rtn -ExcludeProperty UserAccountControl, AccountNotDelegated, AllowReversiblePasswordEncryption, CannotChangePassword, PasswordNeverExpires, SmartcardLogonRequired, TrustedForDelegation
				}
			}
		}
	}
}