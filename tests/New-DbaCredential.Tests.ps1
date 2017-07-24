$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	$logins = "thor", "thorsmomma"
	$plaintext = "BigOlPassword!"
	$password = ConvertTo-SecureString $plaintext -AsPlainText -Force
	
	# Add user
	foreach ($login in $logins) {
		$null = net user $login $plaintext /add
	}
	
	# remove old credentials
	foreach ($instance in $instances) {
		foreach ($Credential in (Get-DbaCredential -SqlInstance $instance)) {
			$Credential.Drop()
		}
	}
	
	Context "Create new credential" {
		It "Should create new credentials with the proper properties" {
			$results = New-DbaCredential -SqlInstance $script:instance1 -Name thorcred -CredentialIdentity thor -Password $password
			$results.Name | Should Be "thorcred"
			$results.Identity | Should Be "thor"
			
			$results = New-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thorsmomma -Password $password
			$results | Should Not Be $null
		}
	}
	
	# Finish up
	foreach ($instance in $instances) {
		foreach ($Credential in (Get-DbaCredential -SqlInstance $instance)) {
			$Credential.Drop()
		}
	}
	
	foreach ($login in $logins) {
		$null = net user $login /delete
	}
}