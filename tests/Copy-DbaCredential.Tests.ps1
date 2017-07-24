$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# Add user
net user thor "BigOlPassword!" /add
net user thorsmomma "BigOlPassword!" /add

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	$Credentials = "thor", "thorsmomma"
	
	foreach ($instance in $instances) {
		foreach ($Credential in (Get-DbaCredential -SqlInstance $instance)) {
			$Credential.Drop()
		}
	}
}

foreach ($instance in $instances) {
	foreach ($Credential in (Get-DbaCredential -SqlInstance $instance)) {
		$Credential.Drop()
	}
}

# Remove user
net user thor /delete
net user thorsmomma /delete
	<#
	$null = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -InputFile C:\github\appveyor-lab\sql2008-scripts\Credentials.sql
	
	Context "Copy Credential with the same properties." {
		It "Should copy successfully" {
			$results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -Credential Tester
			$results.Status | Should Be "Successful"
		}
		
		It "Should retain its same properties" {
			
			$Credential1 = Get-DbaCredential -SqlInstance $script:instance1 -Credential Tester
			$Credential2 = Get-DbaCredential -SqlInstance $script:instance2 -Credential Tester
			
			$Credential2 | Should Not BeNullOrEmpty
			
			# Compare its value
			$Credential1.Name | Should Be $Credential2.Name
			$Credential1.Language | Should Be $Credential2.Language
			$Credential1.Credential | Should be $Credential2.Credential
			$Credential1.DefaultDatabase | Should be $Credential2.DefaultDatabase
			$Credential1.IsDisabled | Should be $Credential2.IsDisabled
			$Credential1.IsLocked | Should be $Credential2.IsLocked
			$Credential1.IsPasswordExpired | Should be $Credential2.IsPasswordExpired
			$Credential1.PasswordExpirationEnabled | Should be $Credential2.PasswordExpirationEnabled
			$Credential1.PasswordPolicyEnforced | Should be $Credential2.PasswordPolicyEnforced
			$Credential1.Sid | Should be $Credential2.Sid
			$Credential1.Status | Should be $Credential2.Status
		}
		
		It "Should Credential with newly created Sql Credential (also tests credential Credential) and gets name" {
			$password = ConvertTo-SecureString -Force -AsPlainText tester1
			$cred = New-Object System.Management.Automation.PSCredential ("tester", $password)
			$s = Connect-DbaSqlServer -SqlInstance $script:instance1 -Credential $cred
			$s.Name | Should Be $script:instance1
		}
	}
	
	Context "No overwrite" {
		$results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -Credential tester -WarningVariable warning  3>&1
		It "Should not attempt overwrite" {
			$warning | Should Match "already exists in destination"
		}
	}
}
#>