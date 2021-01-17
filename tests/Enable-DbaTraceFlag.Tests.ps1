$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'TraceFlag', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying TraceFlag output" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $startingtfs = Get-DbaTraceFlag -SqlInstance $script:instance2
            $safetraceflag = 3226

            if ($startingtfs.TraceFlag -contains $safetraceflag) {
                $server.Query("DBCC TRACEOFF($safetraceflag,-1)")
            }
        }
        AfterAll {
            if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
                $server.Query("DBCC TRACEOFF($safetraceflag,-1)")
            }
        }

        $results = Enable-DbaTraceFlag -SqlInstance $server -TraceFlag $safetraceflag

        It "Return $safetraceflag as enabled" {
            $results.TraceFlag -contains $safetraceflag | Should Be $true
        }
    }
}