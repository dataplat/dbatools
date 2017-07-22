Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
<#Describe "Copy-DbaLogin Integration Tests" -Tags "IntegrationTests" {
	# constants
	$script:sql2008 = "localhost\sql2008r2sp2"
	$script:sql2016 = "localhost\sql2016"
	$Instances = @($script:sql2008, $script:sql2016)
	
	$server = Connect-DbaSqlServer -SqlInstance $script:sql2008
	$sql = Get-Content -Path C:\github\appveyor-lab\sql2008-scripts\logins.sql
	$null = $server.Query($sql)
	
	Context "Copy login with the same properties." {
		It "Should copy successfully" {
			$results = Copy-DbaLogin -Source $script:sql2008 -Destination $script:sql2016 -Login Tester
			$results.Status | Should Be "Successful"
		}
		
		It "Should retain its same properties" {
			
			$login1 = Get-Dbalogin -SqlInstance $script:sql2008 -login Tester
			$login2 = Get-Dbalogin -SqlInstance $script:sql2016 -login Tester
			
			$login2 | Should Not BeNullOrEmpty
			
			# Compare its value
			$login1.Name | Should Be $login2.Name
			$login1.Language | Should Be $login2.Language
			$login1.Credential | Should be $login2.Credential
			$login1.DefaultDatabase | Should be $login2.DefaultDatabase
			$login1.IsDisabled | Should be $login2.IsDisabled
			$login1.IsLocked | Should be $login2.IsLocked
			$login1.IsPasswordExpired | Should be $login2.IsPasswordExpired
			$login1.PasswordExpirationEnabled | Should be $login2.PasswordExpirationEnabled
			$login1.PasswordPolicyEnforced | Should be $login2.PasswordPolicyEnforced
			$login1.Sid | Should be $login2.Sid
			$login1.Status | Should be $login2.Status
		}
	}
}
#>