$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
 	Context "Correctly gets error log messages" {
		$sourceFilter = 'Logon'
		$textFilter = 'All rights reserved'
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

			# (2) Need a login failure, source would be Logon
			$pwd = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
			$sqlCred = New-Object System.Management.Automation.PSCredential($login, $pwd)
			try {
				Connect-DbaSqlServer -SqlInstance $script:instance1 -Credential $sqlCred -ErrorVariable $whatever
			}
			catch {}
		}
		It "Has the correct default properties" {
			$expectedProps = 'ComputerName,InstanceName,SqlInstance,LogDate,Source,Text'.Split(',')
			$results = Get-DbaSqlLog -SqlInstance $script:instance1 -LogNumber 0
			($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($expectedProps | Sort-Object)
		}
		It "Returns filtered results for -Source set to: $sourceFilter]" {
			$results = Get-DbaSqlLog -SqlInstance $script:instance1 -LogNumber 0 -Source $sourceFilter
			$results[0].Source | Should Be $sourceFilter
		}
	}
}