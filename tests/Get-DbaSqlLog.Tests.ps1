$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
 	Context "Correctly gets error log messages" {
		BeforeAll {
			$login = 'DaperDan'
			$l = Get-DbaLogin -SqlInstance $script:instance1 -Login $login
			if ($l) {
				Get-DbaProcess -SqlInstance $instance -Login $login | Stop-DbaProcess
				$l.Drop()
			}
			# (1) Cycle errorlog message: The error log has been reinitialized
			$sql = "EXEC sp_cycle_errorlog;"
			$server = Connect-DbaSqlServer -SqlInstance $script:instance1
			$null = $server.Query($sql)

			# (2) Need 4 login failure: Error 18456, Login failed for user %l
			$loginAttempts = 4
			$pwd = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
			$sqlCred = New-Object System.Management.Automation.PSCredential($login, $pwd)
			for ($e=1; $e -eq $loginAttempts; $e++) {
				$null = Connect-DbaSqlServer -SqlInstance $instance -Credential $sqlCred
			}
		}
		It "Has the correct default properties" {
			$expectedProps = 'ComputerName,InstanceName,SqlInstance,LogDate,Source,Text'.Split(',')
			$results = Get-DbaSqlLog -SqlInstance $script:instance1 -LogNumber 0
			($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($expectedProps | Sort-Object)
		}
		It "Returns filtered results" {
			$filteredText = 'All rights reserved'
			$results = Get-DbaSqlLog -SqlInstance $script:instance1 -LogNumber 0 -Text $filteredText
			$results[0].Text | Should BeLike "*$filteredText*"
		}
	}
}