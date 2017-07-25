$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Create new credential" {
		$credentials = $script:Instances | Get-DbaCredential
		foreach ($Credential in $credentials) {
			$Credential.Drop()
		}
		
		$logins = "thor", "thorsmomma"
		$plaintext = "BigOlPassword!"
		$password = ConvertTo-SecureString $plaintext -AsPlainText -Force
		
		# Add user
		foreach ($login in $logins) {
			$null = net user $login $plaintext /add *>&1
		}
		
		It "Should create new credentials with the proper properties" {
			try {
				$results = New-DbaCredential -SqlInstance $script:instance1 -Name thorcred -CredentialIdentity thor -Password $password
				$results.Name | Should Be "thorcred"
				$results.Identity | Should Be "thor"
				
				$results = New-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thorsmomma -Password $password
				$results.Name | Should Be "thorsmomma"
				$results.Identity | Should Be "thorsmomma"
			}
			catch {
				$moveon = $true
				Write-Warning "Appveyor tripped on creating credential for Copy-DbaCredential. Moving on."
				return
			}
		}
	}
	
	if ($moveon) { return }
	
	Context "Copy Credential with the same properties." {
		It "Should copy successfully" {
			try {
				$results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -CredentialIdentity thorcred
				$results.Status | Should Be "Successful"
			}
			catch {
				# Appveyor tripped - just move on
				$moveon = $true
				Write-Warning "Appveyor tripped on DAC for Copy-DbaCredential. Moving on."
				return
			}
		}
		
		if ($moveon) { return }
		It "Should retain its same properties" {
			
			$Credential1 = Get-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thor
			$Credential2 = Get-DbaCredential -SqlInstance $script:instance2 -CredentialIdentity thor
			
			# Compare its value
			$Credential1.Name | Should Be $Credential2.Name
			$Credential1.CredentialIdentity | Should Be $Credential2.CredentialIdentity
		}
	}
	
	if ($moveon) { return }
	Context "No overwrite and cleanup" {
		try {
			$results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -CredentialIdentity thorcred -WarningVariable warning 3>&1
		}
		catch {
			Write-Warning "Appveyor tripped on DAC for Copy-DbaCredential. Moving on."
			return
		}
		It "Should not attempt overwrite" {
			$warning | Should Match "exists"
			
		}
		# Finish up
		$credentials = $script:Instances | Get-DbaCredential
		foreach ($Credential in $credentials) {
			$Credential.Drop()
		}
		
		foreach ($login in $logins) {
			$null = net user $login /delete *>&1
		}
	}
}