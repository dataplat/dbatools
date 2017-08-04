$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Verifying output" {
		BeforeAll {
			$tfs = 3226,3604
			Write-Host "Quick check on current global TFs enabled"
			$server = Connect-DbaSqlServer -SqlInstance $script:instance1
			$checkResults = $server.Query("DBCC TRACESTATUS(-1)")
			if ($checkResults.Count -gt 0) {
				Write-Host "Found $($checkResults.Count) global TFs enabled, need to disable them" -ForegroundColor Cyan
				foreach ($result in $checkResults) {
					$tf = $result.TraceFlag
					$sql = "DBCC TRACEOFF($tf,-1);"
					$server.Query($sql)
				}
			}
			Write-Host "Enabling global TFs for testing"
			foreach ($tf in $tfs) {
				$sql = "DBCC TRACEON($tf,-1) WITH NO_INFOMSGS;"
				$server.Query($sql)
				Write-Host "$tf enabled"
			}
			$checkResults = $server.Query("DBCC TRACESTATUS(-1)")
			Write-Host "$($CheckResults.Count) TFs enabled."
		}
		AfterAll {
			Write-Host "Cleaning up TFs enabled"
			$server = Connect-DbaSqlServer -SqlInstance $script:instance1
			foreach ($tf in $tfs) {
				$sql = "DBCC TRACEOFF($tf,-1) WITH NO_INFOMSGS;"
				$server.Query($sql)
			}
		}

		It "Has the right default properties" {
			$expectedProps = 'ComputerName,InstanceName,SqlInstance,TraceFlag,Global,Status'.Split(',')
			$results = Get-DbaTraceFlag -SqlInstance $script:instance1
			($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($expectedProps | Sort-Object)
		}
		It "Returns filtered results" {
			$tf = $tfs[0]
			Write-Host "Checking for TF $tf"
			$fResults = Get-DbaTraceFlag -SqlInstance $script:instance1 -TraceFlag $tf
			($fResults | Measure-Object).Count | Should Be 1
		}
		It "Returns following number of TFs: $($tfs.Count)" {
			$results = Get-DbaTraceFlag -SqlInstance $script:instance1
			($results | Measure-Object).Count | Should Be 2
		}
	}
}
