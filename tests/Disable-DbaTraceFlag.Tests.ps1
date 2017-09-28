$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Verifying TraceFlag is disabled" {
		BeforeAll {
			$safetraceflag = 3226
			$server = Connect-DbaSqlServer -SqlInstance $script:instance2
			$startingtfs = $server.Query("DBCC TRACESTATUS(-1)")
			$startingtfscount = $startingtfs.Count
			
			if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
				$server.Query("DBCC TRACEON($safetraceflag,-1)  WITH NO_INFOMSGS")
				$startingtfscount++
			}
		}
		
		It "Count should go back to starting count after disabling TF 3226" {
			$results = Disable-DbaTraceFlag -SqlInstance $script:instance2 -TraceFlag 3226
			$results.TraceFlag.Count | Should Be $startingtfscount
		}
	}
}
