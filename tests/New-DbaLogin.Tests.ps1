$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\Connect-SqlInstance.ps1"
. "$PSScriptRoot\..\internal\Get-PasswordHash.ps1"
. "$PSScriptRoot\..\internal\Convert-HexStringToByte"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
		
	$credLogin = 'credologino'
	$certificateName = 'DBAToolsPesterlogincertificate'
	$password = 'MyV3ry$ecur3P@ssw0rd'
	$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
	$sid = '0xDBA700131337C0D30123456789ABCDEF'
	$server = Connect-SqlInstance -SqlInstance $script:instance1
	$server1 = $server
	$server2 = Connect-SqlInstance -SqlInstance $script:instance2
	$computerName = $server.NetName
	$winLogin = "$computerName\$credLogin"
	$logins = "claudio", "port", "tester", "certifico", $winLogin
	
	#cleanup
	foreach ($instance in $instances) {
		foreach ($login in $logins) {
			if ($l = Get-DbaLogin -SqlInstance $instance -Login $login) {
				Get-DbaProcess -SqlInstance $instance -Login $login | Stop-DbaProcess
				if ($c = $l.EnumCredentials()) {
					$l.DropCredential($c)
				}
				$l.Drop()
			}
		}
	}
	
	#create Windows login
	$computer = [ADSI]"WinNT://$computerName"
	try {
		$user = [ADSI]"WinNT://$computerName/$credLogin,user"
		if ($user.Name -eq $credLogin) {
			$computer.Delete('User',$credLogin)
		}
	}
	catch {<#User does not exist#>}
	
	$user = $computer.Create("user", $credLogin)
	$user.SetPassword($password)
	$user.SetInfo()
	
	#create credential
	$null = New-DbaCredential -SqlInstance $script:instance1 -Name $credLogin -CredentialIdentity $credLogin -Password $securePassword -Force
	
	#create master key if not exists
	if (!($mkey = Get-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master)) {
		$null = New-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master -Password $securePassword -Confirm:$false
	}
	
	#create certificate
	if ($crt = $server.Databases['master'].Certificates[$certificateName]) {
		$crt.Drop()
	}
	$null = New-DbaDatabaseCertificate $script:instance1 -Name $certificateName -Password $null
	
	Context "Create new logins." {
		It "Should be created successfully - Hashed password" {
			$results = New-DbaLogin -SqlInstance $script:instance1 -Login tester -HashedPassword (Get-PasswordHash $securePassword (Connect-SqlInstance -SqlInstance $script:instance1).VersionMajor)
			$results.Status | Should Be "Successful"
		}
		It "Should be created successfully - password, credential and a custom sid " {
			$results = New-DbaLogin -SqlInstance $script:instance1 -Login claudio -Password $securePassword -Sid $sid -MapToCredential $credLogin
			$results.Status | Should Be "Successful"
		}
		It "Should be created successfully - password and all the flags" {
			$results = New-DbaLogin -SqlInstance $script:instance1 -Login port -Password $securePassword -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands
			$results.Status | Should Be "Successful"
		}
		It "Should be created successfully - Windows login" {
			$results = New-DbaLogin -SqlInstance $script:instance1 -Login $winLogin
			$results.Status | Should Be "Successful"
		}
		It "Should be created successfully - certificate" {
			$results = New-DbaLogin -SqlInstance $script:instance1 -Login certifico -MapToCertificate $certificateName
			$results.Status | Should Be "Successful"
		}
		It "Should have specific parameters" {
			$login1 = Get-Dbalogin -SqlInstance $script:instance1 -login claudio
			$login2 = Get-Dbalogin -SqlInstance $script:instance1 -login port
				
			$login1.EnumCredentials() | Should be $credLogin
			$login1.DefaultDatabase | Should be 'master'
			$login1.IsDisabled | Should be $false
			$login1.PasswordExpirationEnabled | Should be $false
			$login1.PasswordPolicyEnforced | Should be $false
			$login1.Sid | Should be (Convert-HexStringToByte $sid)
			
			$login2.Language | Should Be 'Nederlands'
			$login2.EnumCredentials() | Should be $null
			$login2.DefaultDatabase | Should be 'tempdb'
			$login2.IsDisabled | Should be $true
			$login2.PasswordExpirationEnabled | Should be $true
			$login2.PasswordPolicyEnforced | Should be $true
		}
		
		It "Should be copied successfully" {
			$results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | New-DbaLogin -SqlInstance $script:instance2 -Disabled:$false
			$results.Status | Should Be "Successful"
			
			$results = Get-DbaLogin -SqlInstance $script:instance1 -Login claudio,port | New-DbaLogin -SqlInstance $script:instance2 -Force -PasswordPolicy -PasswordExpiration -DefaultDatabase tempdb -Disabled -Language Nederlands -NewSid -LoginRenameHashtable @{claudio = 'port'; port = 'claudio'} -MapToCredential $null
			$results.Status | Should Be @("Successful", "Successful")
			
			$results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | New-DbaLogin -SqlInstance $script:instance1 -LoginRenameHashtable @{tester = 'port'} -Force -NewSid
			$results.Status | Should Be "Successful"
		}
		
		It "Should retain its same properties" {
			
			$login1 = Get-Dbalogin -SqlInstance $script:instance1 -login tester
			$login2 = Get-Dbalogin -SqlInstance $script:instance2 -login tester
			
			$login2 | Should Not BeNullOrEmpty
			
			# Compare values
			$login1.Name | Should Be $login2.Name
			$login1.Language | Should Be $login2.Language
			$login1.EnumCredentials() | Should be $login2.EnumCredentials()
			$login1.DefaultDatabase | Should be $login2.DefaultDatabase
			$login1.IsDisabled | Should be $login2.IsDisabled
			$login1.PasswordExpirationEnabled | Should be $login2.PasswordExpirationEnabled
			$login1.PasswordPolicyEnforced | Should be $login2.PasswordPolicyEnforced
			$login1.Sid | Should be $login2.Sid
		}
		
		It "Should not have same properties because of the overrides" {
			
			$login1 = Get-Dbalogin -SqlInstance $script:instance1 -login claudio
			$login2 = Get-Dbalogin -SqlInstance $script:instance2 -login port
			
			$login2 | Should Not BeNullOrEmpty
			
			# Compare values
			$login1.Language | Should Not Be $login2.Language
			$login1.EnumCredentials() | Should Not Be $login2.EnumCredentials()
			$login1.DefaultDatabase | Should Not be $login2.DefaultDatabase
			$login1.IsDisabled | Should Not be $login2.IsDisabled
			$login1.PasswordExpirationEnabled | Should Not be $login2.PasswordExpirationEnabled
			$login1.PasswordPolicyEnforced | Should Not be $login2.PasswordPolicyEnforced
			$login1.Sid | Should Not be $login2.Sid
		}
	}
	Context "Connect with a new login" {
		It "Should login with newly created Sql Login (also tests credential login) and get instance name" {
			$cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
			$s = Connect-SqlInstance -SqlInstance $script:instance1 -SqlCredential $cred
			$s.Name | Should Be $script:instance1
		}
		It "Should return existing process running under the new login and kill it" {
			$cred = New-Object System.Management.Automation.PSCredential ("tester", $securePassword)
			$results = Get-DbaProcess -SqlInstance $script:instance1 -Login $cred.UserName
			$results | Should Not BeNullOrEmpty
			$results = $results | Stop-DbaProcess
			$results.Status | Should be 'Killed'
		}
	}
	
	Context "No overwrite" {
		$results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | New-DbaLogin -SqlInstance $script:instance2 -WarningVariable warning  3>&1
		It "Should not attempt overwrite" {
			$warning | Should Match "Login tester already exists"
		}
	}
	
	#Cleanup
	foreach ($instance in $instances) {
		foreach ($login in $logins) {
			if ($l = Get-DbaLogin -SqlInstance $instance -Login $login) {
				Get-DbaProcess -SqlInstance $instance -Login $login | Stop-DbaProcess
				if ($c = $l.EnumCredentials()) {
					$l.DropCredential($c)
				}
				$l.Drop()
			}
		}
	}
	$computer.Delete('User',$credLogin) 
	$server.Credentials[$credLogin].Drop()
	$server.Databases['master'].Certificates[$certificateName].Drop()
	if (!$mkey) {
		$null = Remove-DbaDatabaseMasterKey -SqlInstance $script:instance1 -Database master -Confirm:$false
	}
}
