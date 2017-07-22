$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	. .\tests\constants.ps1
	return
	$Credentials = "claudio", "port", "tester"
	New-LocalUser -Name "User02" -Description "Description of this account." -NoPassword
	
	foreach ($instance in $instances) {
		foreach ($Credential in $Credentials) {
			if ($l = Get-DbaCredential -SqlInstance $instance -Credential $Credential) {
				Get-DbaProcess -SqlInstance $instance -Credential $Credential | Stop-DbaProcess
				$l.Drop()
			}
		}
	}
	
	$null = Invoke-Sqlcmd2 -ServerInstance $script:sql2008 -InputFile C:\github\appveyor-lab\sql2008-scripts\Credentials.sql
	
	Context "Copy Credential with the same properties." {
		It "Should copy successfully" {
			$results = Copy-DbaCredential -Source $script:sql2008 -Destination $script:sql2016 -Credential Tester
			$results.Status | Should Be "Successful"
		}
		
		It "Should retain its same properties" {
			
			$Credential1 = Get-DbaCredential -SqlInstance $script:sql2008 -Credential Tester
			$Credential2 = Get-DbaCredential -SqlInstance $script:sql2016 -Credential Tester
			
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
			$s = Connect-DbaSqlServer -SqlInstance $script:sql2008 -Credential $cred
			$s.Name | Should Be $script:sql2008
		}
	}
	
	Context "No overwrite" {
		$results = Copy-DbaCredential -Source $script:sql2008 -Destination $script:sql2016 -Credential tester -WarningVariable warning  3>&1
		It "Should not attempt overwrite" {
			$warning | Should Match "already exists in destination"
		}
	}
}
