$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Disable-DbaTraceFlag).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'TraceFlag', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying TraceFlag output" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $startingtfs = Get-DbaTraceFlag -SqlInstance $server
            $safetraceflag = 3226

            if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
                $null = $server.Query("DBCC TRACEON($safetraceflag,-1)")
            }

        }
        AfterAll {
            if ($startingtfs.TraceFlag -contains $safetraceflag) {
                $server.Query("DBCC TRACEON($safetraceflag,-1)  WITH NO_INFOMSGS")
            }
        }

        $results = Disable-DbaTraceFlag -SqlInstance $server -TraceFlag $safetraceflag

        It "Return $safetraceflag as disabled" {
            $results.TraceFlag -contains $safetraceflag | Should Be $true
        }
    }
}