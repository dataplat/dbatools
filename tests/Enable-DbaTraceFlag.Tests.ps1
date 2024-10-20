param($ModuleName = 'dbatools')

Describe "Enable-DbaTraceFlag" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Enable-DbaTraceFlag
        }
        $parms = @(
            'SqlInstance',
            'SqlCredential',
            'TraceFlag',
            'EnableException'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying TraceFlag output" -Tag "IntegrationTests" {
        BeforeAll {
            $global:server = Connect-DbaInstance -SqlInstance $global:instance2
            $global:startingtfs = Get-DbaTraceFlag -SqlInstance $global:instance2
            $global:safetraceflag = 3226

            if ($global:startingtfs.TraceFlag -contains $global:safetraceflag) {
                $global:server.Query("DBCC TRACEOFF($global:safetraceflag,-1)")
            }
        }
        AfterAll {
            if ($global:startingtfs.TraceFlag -notcontains $global:safetraceflag) {
                $global:server.Query("DBCC TRACEOFF($global:safetraceflag,-1)")
            }
        }

        It "Returns $global:safetraceflag as enabled" {
            $results = Enable-DbaTraceFlag -SqlInstance $global:server -TraceFlag $global:safetraceflag
            $results.TraceFlag | Should -Contain $global:safetraceflag
        }
    }
}
