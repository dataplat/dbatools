$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	Context "Verifying TraceFlag output" {
		BeforeAll {
			$safetraceflag = 3226
		}
		AfterAll {
			if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
				$server.Query("DBCC TRACEOFF($safetraceflag,-1)")
			}
		}
		
		It "Has the right default properties" {
			$expectedProps = 'ComputerName,InstanceName,SqlInstance,TraceFlag,Global,Status'.Split(',')
			$results = Get-DbaTraceFlag -SqlInstance $script:instance2
			($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($expectedProps | Sort-Object)
		}
		
		It "Return 3226 as enabled" {
			$results = Enable-DbaTraceFlag -SqlInstance $script:instance2 -TraceFlag 3226
			$results.TraceFlag | Should Be 3226
		}
	}
}
