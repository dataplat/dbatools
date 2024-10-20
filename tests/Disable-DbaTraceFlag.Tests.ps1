param($ModuleName = 'dbatools')

Describe "Disable-DbaTraceFlag" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Disable-DbaTraceFlag
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
            $server = Connect-DbaInstance -SqlInstance $global:instance1
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

        It "Returns $safetraceflag as disabled" {
            $results = Disable-DbaTraceFlag -SqlInstance $server -TraceFlag $safetraceflag
            $results.TraceFlag | Should -Contain $safetraceflag
        }
    }
}
