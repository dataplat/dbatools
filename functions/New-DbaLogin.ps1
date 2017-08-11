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
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Password")]
	param (
		[parameter(Mandatory)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Name", "LoginName")]
		[parameter(ParameterSetName = "Password")]
		[parameter(ParameterSetName = "PasswordHash")]
		[parameter(ParameterSetName = "MapToCertificate")]
		[parameter(ParameterSetName = "MapToAsymmetricKey")]
		[string[]]$Login,
		[parameter(ValueFromPipeline = $true)]
		[parameter(ParameterSetName = "Password")]
		[parameter(ParameterSetName = "PasswordHash")]
		[parameter(ParameterSetName = "MapToCertificate")]
		[parameter(ParameterSetName = "MapToAsymmetricKey")]
		[object[]]$InputObject,
		[hashtable]$LoginRenameHashtable,
		[parameter(ParameterSetName = "Password")]
		[Security.SecureString]$Password,
		[parameter(ParameterSetName = "PasswordHash")]
		[string]$HashedPassword,
		[parameter(ParameterSetName = "MapToCertificate")]
		[string]$MapToCertificate,
		[parameter(ParameterSetName = "MapToAsymmetricKey")]
		[string]$MapToAsymmetricKey,
		[string]$MapToCredential,
		[object]$Sid,
		[Alias("DefaulDB")]
		[parameter(ParameterSetName = "Password")]
		[parameter(ParameterSetName = "PasswordHash")]
		[string]$DefaultDatabase,
		[parameter(ParameterSetName = "Password")]
		[parameter(ParameterSetName = "PasswordHash")]
		[string]$Language,
		[Alias("Expiration","CheckExpiration")]
		[parameter(ParameterSetName = "Password")]
		[parameter(ParameterSetName = "PasswordHash")]
		[switch]$PasswordExpiration,
		[Alias("Policy","CheckPolicy")]
		[parameter(ParameterSetName = "Password")]
		[parameter(ParameterSetName = "PasswordHash")]
		[switch]$PasswordPolicy,
		[switch]$NewSid,
		[switch]$Force,
		[switch]$Silent
	)
	
	begin {
		# function to convert byte object (@(1,100,23,54)) into hex sring (0x01641736)
		function Convert-ByteToHexString {
			Param ([byte[]]$InputObject)
			$outString = "0x"; $InputObject | ForEach-Object { $outString += ("{0:X}" -f $_).PadLeft(2, "0") }
			Return $outString
		}
		# function to convert hex string (0x01641736) into byte object (@(1,100,23,54))
		function Convert-HexStringToByte {
			Param ([string]$InputObject)
			$hexString = $InputObject.TrimStart("0x")
			if ($hexString.Length % 2 -eq 1) { $hexString = '0' + $hexString }
			[byte[]]$outByte = $null; $outByte += 0 .. (($hexString.Length)/2-1) | ForEach-Object { [Int16]::Parse($hexString.Substring($_*2, 2), 'HexNumber') }
			Return $outByte
		}
		
		<#
		if ($loginCollection.Length -gt 1 -and ($Sid -or $MapToCertificate -or $MapToAsymmetricKey -or $MapToCredential)) {
			Stop-Function -Message "Please specify a single login when using one of the following parameters: -Sid, -MapToCertificate, -MapToAsymmetricKey, -MapToCredential." -Category InvalidArgument -Silent $Silent
			Return
		}
		#>

		if ($Sid) {
			if ($Sid.GetType().Name -ne 'Byte[]') {
				$Sid = Convert-HexStringToByte $Sid
			}
		}
		
		if ($HashedPassword) {
			if ($HashedPassword.GetType().Name -eq 'Byte[]') {
				$HashedPassword = Convert-ByteToHexString $HashedPassword 
			}
		}
	}
	
	process {
		#At least one of those should be specified
		if (!($Login -or $InputObject)) {
			Stop-Function -Message "No logins have been specified." -Category InvalidArgument -Silent $Silent
			Return
		}
		
		$loginCollection = @()
		if ($InputObject) {
			$loginCollection += $InputObject
			if ($Login) {
				Stop-Function -Message "Parameter -Login is not supported when processing objects from -InputObject. If you need to rename the logins, please use -LoginRenameHashtable." -Category InvalidArgument -Silent $Silent
				Return
			}
		}
		else {
			$loginCollection += $Login
			$Login | ForEach-Object { 
				if ($_.IndexOf('\') -eq -1 -and $PsCmdlet.ParameterSetName -like "Password*" -and !($Password -or $HashedPassword)) {
					$passwordNotSpecified = $true
				}
			}
		}
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Silent $Silent -Continue
			}
			
			foreach ($loginItem in $loginCollection) {
				#check if $loginItem is an SMO Login object
				if ($loginItem.GetType().Name -eq 'Login') {
					$loginName = $loginItem.Name
					$loginType = $loginItem.LoginType
					$currentSid = $loginItem.Sid
					
					#Get previous password
					if ($loginType -eq 'SqlLogin' -and !($Password -or $HashedPassword)) {
						$sourceServer = $loginItem.Parent
						switch ($sourceServer.versionMajor) {
							0 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$loginName'" }
							8 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM dbo.syslogins WHERE name='$loginName'" }
							9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins where name='$loginName'" }
							default {
								$sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash')
									AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass FROM sys.server_principals
									WHERE principal_id = $($loginItem.id)"
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
							$hashedPass = Convert-ByteToHexString $hashedPass
						}
						$currentHashedPassword = $hashedPass
					}
					
					if ($loginType -eq 'AsymmetricKey' -and !$MapToAsymmetricKey) {
						$MapToAsymmetricKey = $login.AsymmetricKey
					}
					if ($loginType -eq 'Certificate' -and !$MapToCertificate) {
						$MapToCertificate = $login.Certificate
					}
				}
				else {
					$loginName = $loginItem
					$currentSid = $Sid
					if ($PsCmdlet.ParameterSetName -eq "MapToCertificate") { $loginType = 'Certificate' }
					elseif ($PsCmdlet.ParameterSetName -eq "MapToAsymmetricKey") { $loginType = 'AsymmetricKey' }
					elseif ($loginItem.IndexOf('\') -eq -1) {	$loginType = 'SqlLogin' }
					else { $loginType = 'WindowsUser' }
				}
				
				#Apply renaming if necessary
				if ($LoginRenameHashtable.Keys -contains $loginName) {
					$loginName = $LoginRenameHashtable[$loginName]
				}
				
				#Requesting password if required
				if ($loginItem.GetType().Name -ne 'Login' -and $loginType -eq 'SqlLogin' -and !($Password -or $HashedPassword)) {	
					$Password = Read-Host -AsSecureString -Prompt "Enter a new password for the SQL Server login(s)"
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
						Write-Message -Level Verbose -Message "Dropping login $loginName on $instance"
						try {
							$existingLogin.Drop()
						}
						catch {
							Stop-Function -Message "Could not remove existing login $loginName on $instance, skipping." -Target $loginName -Silent $Silent -Continue
						}
					}
					else {
						Stop-Function -Message "Login $loginName exists on $instance and -Force was not specified" -Target $loginName -Silent $Silent -Continue
					}
				}
				
				
				if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating login $loginName on $instance")) {
					try {
						Write-Message -Level Verbose -Message "Attempting to create login $loginName on $instance."
						$newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $loginName)
						$newLogin.LoginType = $loginType
						
						$withParams = ""
						
						if ($loginType -eq 'SqlLogin' -and $currentSid -and !$NewSid) {
							Write-Message -Level Verbose -Message "Setting $loginName SID"
							$withParams += ", SID = " + (Convert-ByteToHexString $currentSid)
							$newLogin.Set_Sid($currentSid)
						}
						
						if ($loginType -in ("WindowsUser","WindowsGroup","SqlLogin")) {
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
							if ($Password) {
								$currentHashedPassword = Generate-DbaPasswordHash $Password $server.Version.Major
							}
							elseif ($HashedPassword) {
								$currentHashedPassword = $HashedPassword
							}
						}
						elseif ($loginType -eq 'AsymmetricKey') {
									$newLogin.AsymmetricKey = $MapToAsymmetricKey }
						
						Write-Message -Level Verbose -Message "Adding as login type $loginType"
						
						# Attempt to add SQL Login User
						if ($loginType -eq "SqlLogin") {
							try {
								$newLogin.Create($currentHashedPassword, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
								$newLogin.Refresh()
								Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
	
								$newLoginStatus.Status = "Successful"
							}
							catch {
								Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL."
								try {
									$sql = "CREATE LOGIN [$loginName] WITH PASSWORD = $currentHashedPassword HASHED" + $withParams
	
									$null = $server.Query($sql)
	
									$newLogin = $server.logins[$loginName]
									Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
	
									$newLoginStatus.Status = "Successful"
	
								}
								catch {
									$newLoginStatus.Status = "Failed"
									$newLoginStatus.Notes = $_.Exception.GetBaseException().Message
									$newLoginStatus
									Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Silent $Silent -Continue 3>$null
								}
							}
						}
						# Attempt to add Windows User
						elseif ($loginType -in ("WindowsUser","WindowsGroup")) {
							try {
								$newLogin.Create()
								$newLogin.Refresh()
								Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
	
								$newLoginStatus.Status = "Successful"
							}
							catch {
								Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL."
								try {
									if ($withParams) { $withParams = " WITH " + $withParams.TrimStart(',') }
									$sql = "CREATE LOGIN [$loginName] FROM WINDOWS" + $withParams
	
									$null = $server.Query($sql)
	
									$newLogin = $server.logins[$loginName]
									Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
	
									$newLoginStatus.Status = "Successful"
								}
								catch {
									$newLoginStatus.Status = "Failed"
									$newLoginStatus.Notes = $_.Exception.GetBaseException().Message
									$newLoginStatus
									Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Silent $Silent -Continue 3>$null
								}
							}
						}
						# Create login from AsymmetricKey or Certificate
						elseif ($loginType -in ('AsymmetricKey','Certificate')) {
							try {
								if ($loginType -eq 'AsymmetricKey') { $newLogin.AsymmetricKey = $MapToAsymmetricKey }
							  elseif ($loginType -eq 'Certificate') { $newLogin.Certificate = $MapToCertificate }
								$newLogin.Create()
								$newLogin.Refresh()
								Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
		
								$newLoginStatus.Status = "Successful"
							}
							catch {
								Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL."
								try {
									if ($loginType -eq 'AsymmetricKey') { $sql = "CREATE LOGIN [$loginName] FROM ASYMMETRIC KEY [$MapToAsymmetricKey]" }
									elseif ($loginType -eq 'Certificate') { $sql = "CREATE LOGIN [$loginName] FROM CERTIFICATE [$MapToCertificate]" }
	
									$null = $server.Query($sql)
	
									$newLogin = $server.logins[$loginName]
									Write-Message -Level Verbose -Message "Successfully added $loginName to $instance."
	
									$newLoginStatus.Status = "Successful"
								}
								catch {
									$newLoginStatus.Status = "Failed"
									$newLoginStatus.Notes = $_.Exception.GetBaseException().Message
									$newLoginStatus
									Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Silent $Silent -Continue 3>$null
								}
							}
						}		
						#Display results
						$newLoginStatus
						
						#Add credential
						if ($MapToCredential) {
							Write-Message -Level Verbose -Message "Mapping $loginName to the credential $MapToCredential"
							try {
								$newLogin.AddCredential($MapToCredential)
							}
							catch {
								Write-Message -Level Verbose -Message "Failed to map $loginName to the credential $MapToCredential on $instance using SMO, trying T-SQL."
								try {
									$sql = "ALTER LOGIN [$loginName] ADD CREDENTIAL [$MapToCredential]"
	
									$null = $server.Query($sql)
	
									Write-Message -Level Verbose -Message "Successfully mapped $loginName to the credential $MapToCredential on $instance."	
								}
								catch {									
									Stop-Function -Message "Failed to map $loginName to the credential $MapToCredential on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Silent $Silent -Continue
								}
							}
						}
					}
					catch {
						Stop-Function -Message "Failed to create login $loginName on $instance. Exception: $($_.Exception.InnerException)" -Target $credential -Silent $Silent -InnerErrorRecord $_ -Continue
					}
				}
			}
		}
	}
}

<#

import-module C:\Git\nvarscar-dbatools\new-dbalogin\dbatools
#Get-DbaLogin -SqlInstance 'wpg1lsds01,7220' -Login 'BakReports'|New-DbaLogin -SqlInstance 'wpg1lsds01,7220' -LoginRenameHashtable @{BakReports = 'Test2'} -Force
#New-DbaLogin -SqlInstance 'wpg1lsds01,7220' -Force -NewSid -HashedPassword 0x0200BE5E02140D98881D689DA864C447D2E6D49C3E9DC10099C4A34110C82E503349D8ACF10B49455CD8FADA810BC9EB7315DCB6A4C3C7222C84E46B4C283AD3B0B50DB274F7 -Login Test5, Test6, Test7 

New-DbaLogin -SqlInstance 'wpg1lsds01,7220' -Force -NewSid -Login Test5, Test6, Test7 -MapToCertificate 'asd'
#>