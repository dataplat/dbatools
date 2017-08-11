function New-DbaLogin {
<#
	.SYNOPSIS
	Creates a new SQL Server login
	
	.DESCRIPTION
	Creates a new SQL Server login with provided specifications
		
	.PARAMETER SqlInstance
	The target SQL Server(s)
	
	.PARAMETER SqlCredential
	Allows you to login to SQL Server using alternative credentials
	
	.PARAMETER Name
	The Login name
		
	.PARAMETER Password
	Secure string used to authenticate the Credential Identity
	
	
	.PARAMETER Force
	If credential exists, drop and recreate 
		
	.PARAMETER WhatIf 
	Shows what would happen if the command were to run. No actions are actually performed 
	
	.PARAMETER Confirm 
	Prompts you for confirmation before executing any changing operations within the command 
	
	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages
	
	.NOTES
	Tags: Certificate
	
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
	.EXAMPLE
	New-DbaCredential -SqlInstance Server1
	
	You will be prompted to securely enter your password, then a credential will be created in the master database on server1 if it does not exist.
	
	.EXAMPLE
	New-DbaCredential -SqlInstance Server1 -Database db1 -Confirm:$false
	
	Suppresses all prompts to install but prompts to securely enter your password and creates a credential in the 'db1' database
#>
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "RegularLogin")]
	param (
		[parameter(Mandatory)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[parameter(Mandatory, ValueFromPipeline = $true)]
		[Alias("Login", "LoginName")]
		[object[]]$Name,
		[parameter(ParameterSetName = "RegularLogin")]
		[Security.SecureString]$Password,
		[parameter(ParameterSetName = "RegularLogin")]
		[string]$HashedPassword,
		[parameter(ParameterSetName = "MapToCertificate")]
		[string]$MapToCertificate,
		[parameter(ParameterSetName = "MapToAssymetricKey")]
		[string]$MapToAssymetricKey,
		[string[]]$MapToCredential,
		[object]$Sid,
		[Alias("DefaulDB")]
		[string]$DefaultDatabase,
		[string]$Language,
		[Alias("Expiration","CheckExpiration")]
		[switch]$PasswordExpiration,
		[Alias("Policy","CheckPolicy")]
		[switch]$PasswordPolicy,
		[switch]$Force,
		[switch]$Silent
	)
	
	begin {
		if ($Password -and $HashedPassword) {
			Stop-Function -Message "Please specify only one password parameter at a time." -Category InvalidArgument -Silent $Silent
		}
		
		if ($Name.Length -gt 1 -and ($Sid -or $MapToCertificate -or $MapToAssymetricKey -or $HashedPassword)) {
			Stop-Function -Message "Please specify a single login when using one of the following parameters: -Sid, -MapToCertificate, -MapToAssymetricKey, -HashedPassword." -Category InvalidArgument -Silent $Silent
		}
		
		foreach ($login in $Name) {
			if ($login.GetType().Name -eq 'Login') {
				if ($login.LoginType -eq 'SqlLogin' -and !($Password -or $HashedPassword)) {
					$passwordNotSpecified = $true
				}
			}
			else {
				if ($login.IndexOf('\') -eq -1 -and $PsCmdlet.ParameterSetName -eq "RegularLogin" -and !($Password -or $HashedPassword)) {
					$passwordNotSpecified = $true
				}
			}
		}
			
		if ($passwordNotSpecified) {	
			$Password = Read-Host -AsSecureString -Prompt "Enter a new password for the SQL Server login(s)"
			if (!$Password) {
				Stop-Function -Message "If at least one SqlLogin is being created -Password (or -HashedPassword) parameter should be provided." -Category InvalidArgument -Silent $Silent
			}
		}
		if ($Sid) {
			if ($Sid.GetType().Name -eq 'Byte[]') {
				$stringSid = "0x"; $Sid | ForEach-Object { $stringSid += ("{0:X}" -f $_).PadLeft(2, "0") }
				$byteSid = $Sid
			}
			elseif (!($Sid.StartsWith('0x'))) {
				Stop-Function -Message "Invalid sid string `"$Sid`". Please make sure that it starts with 0x." -Category InvalidArgument -Silent $Silent
			}
			else {
				$stringSid = $Sid
				$hexSid = $Sid.TrimStart("0x")
				[byte[]]$byteSid = $null; $byteSid += 0 .. ([math]::Round(($hexSid.Length)/2)-1) | ForEach-Object { [Int16]::Parse($hexSid.Substring($_*2, 2), 'HexNumber') }
			}
		}
		
	}
	
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Silent $Silent -Continue
			}
			
			foreach ($login in $Name) {
				#check if Name is a login SMO object
				if ($login.GetType().Name -eq 'Login') {
					$loginName = $login.Name
					$loginType = $login.LoginType
				}
				else {
					$loginName = $login
					if ($PsCmdlet.ParameterSetName -eq "MapToCertificate") { $loginType = 'Certificate' }
					elseif ($PsCmdlet.ParameterSetName -eq "MapToAssymetricKey") { $loginType = 'AssymetricKey' }
					elseif ($login.IndexOf('\') -eq -1) {	$loginType = 'SqlLogin' }
					else { $loginType = 'WindowsUser' }
				}
				
				$newLoginStatus = [pscustomobject]@{
					Server = $server.Name
					Login = $loginName
					Type = $loginType
					Status = $null
					Notes = $null
					DateTime = [DbaDateTime](Get-Date)
				}
				
				#verify if login exists on the server
				$existingLogin = $server.Logins[$loginName]
				
				if ($existingLogin) {
					if ($force) {
						Write-Message -Level Verbose -Message "Dropping login $name"
						$existingLogin.Drop()
					}
					else {
						Stop-Function -Message "Login exists and Force was not specified" -Target $name -Silent $Silent -Continue
					}
				}
				
				
				if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating login $loginName on $instance")) {
					try {
						Write-Message -Level Verbose -Message "Attempting to create login $loginName on $instance."
						$newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $loginName)
						$newLogin.LoginType = $loginType
						
						$withParams = ""
						
						if ($Sid) {
							Write-Message -Level Verbose -Message "Setting $loginName SID"
							$withParams += ", SID = $stringSid"
							$newLogin.Set_Sid($byteSid)
						}
						
						if ($DefaultDatabase) {
							Write-Message -Level Verbose -Message "Setting $loginName default database to $DefaultDatabase"
							$withParams += ", DEFAULT_DATABASE = [$DefaultDatabase]"
							$newLogin.DefaultDatabase = $DefaultDatabase
						}
						
						if ($Language) {
							Write-Message -Level Verbose -Message "Setting $loginName language to $Language"
							$withParams += ", DEFAULT_LANGUAGE = [$Language]"
							$newLogin.Language = $Language
							$
						}
						
						if ($PasswordExpiration) {
							$withParams += ", CHECK_EXPIRATION = ON"
							$newLogin.PasswordExpirationEnabled = $true
						}
						else {
							$withParams += ", CHECK_EXPIRATION = OFF"
							$newLogin.PasswordExpirationEnabled = $false
						}
						
						if ($PasswordPolicy) {
							$withParams += ", CHECK_POLICY = ON"
							$newLogin.PasswordPolicyEnforced = $true
						}
						else {
							$withParams += ", CHECK_POLICY = OFF"
							$newLogin.PasswordPolicyEnforced = $false
						}
						
						#Generate hashed password if necessary
						if (!$HashedPassword) {
								$HashedPassword = Generate-DbaPasswordHash $Password $server.Version.Major
						}
	
						# Attempt to add SQL Login User
						if ($loginType -eq "SqlLogin") {

							try {
								$newLogin.Create($HashedPassword, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
								$newLogin.Refresh()
								Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
	
								$newLoginStatus.Status = "Successful"
								$newLoginStatus

							}
							catch {
								try {
									$sql = "CREATE LOGIN [$loginName] WITH PASSWORD = $hashedPass HASHED, SID = $sid,
													DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkpolicy,
													CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$($sourceLogin.Language)]"
	
									$null = $destServer.Query($sql)
	
									$destLogin = $destServer.logins[$userName]
									Write-Message -Level Verbose -Message "Successfully added $userName to $destination."
	
									$copyLoginStatus.Status = "Successful"
									$copyLoginStatus
	
								}
								catch {
									$copyLoginStatus.Status = "Failed"
									$copyLoginStatus.Notes = $_.Exception.Message
									$copyLoginStatus
									
									Stop-Function -Message "Failed to add $userName to $destination." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Silent $Silent -Continue 3>$null
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
								Write-Message -Level Verbose -Message "Successfully added $userName to $destination."
	
								$copyLoginStatus.Status = "Successful"
								$copyLoginStatus
	
							}
							catch {
								$copyLoginStatus.Status = "Failed"
								$copyLoginStatus.Notes = $_.Exception.Message
								$copyLoginStatus
								
								Stop-Function -Message "Failed to add $userName to $destination" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
							}
						}
						# This script does not currently support certificate mapped or asymmetric key users.
						else {
							Write-Message -Level Warning -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.name) skipped."
	
							$copyLoginStatus.Status = "Skipped"
							$copyLoginStatus.Notes = "$($sourceLogin.LoginType) not supported"
							$copyLoginStatus
	
							continue
						}

					}
					catch {
						Stop-Function -Message "Failed to create credential in $cred on $instance. Exception: $($_.Exception.InnerException)" -Target $credential -Silent $Silent -InnerErrorRecord $_ -Continue
					}
				}
			}
		}
	}
}