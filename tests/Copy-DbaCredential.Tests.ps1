$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

if ($env:appveyor) {
	try {
		$connstring = "Server=ADMIN:$script:instance1;Trusted_Connection=True"
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $script:instance1
		$server.ConnectionContext.ConnectionString = $connstring
		$server.ConnectionContext.Connect()
		$server.ConnectionContext.Disconnect()
		Clear-DbaSqlConnectionPool
	}
	catch {
		Write-Host "DAC not working this round, likely due to Appveyor resources"
		return
	}
}

# One more for the road - clearing the connection pool is important for DAC since only one is allowed
Clear-DbaSqlConnectionPool

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
			$results = New-DbaCredential -SqlInstance $script:instance1 -Name thorcred -CredentialIdentity thor -Password $password
			$results.Name | Should Be "thorcred"
			$results.Identity | Should Be "thor"
			
			$results = New-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thorsmomma -Password $password
			$results.Name | Should Be "thorsmomma"
			$results.Identity | Should Be "thorsmomma"
		}
	}
	Clear-DbaSqlConnectionPool
	Context "Copy Credential with the same properties." {
		It "Should copy successfully" {
			$results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -CredentialIdentity thorcred
			$results.Status | Should Be "Successful"
		}
		
		It "Should retain its same properties" {
			
			$Credential1 = Get-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thor
			$Credential2 = Get-DbaCredential -SqlInstance $script:instance2 -CredentialIdentity thor
			
			# Compare its value
			$Credential1.Name | Should Be $Credential2.Name
			$Credential1.CredentialIdentity | Should Be $Credential2.CredentialIdentity
		}
	}
	Clear-DbaSqlConnectionPool
	Context "No overwrite and cleanup" {
		$results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -CredentialIdentity thorcred -WarningVariable warning 3>&1
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
	Clear-DbaSqlConnectionPool
}