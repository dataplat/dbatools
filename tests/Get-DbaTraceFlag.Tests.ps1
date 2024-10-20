param($ModuleName = 'dbatools')

Describe "Get-DbaTraceFlag" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaTraceFlag
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "TraceFlag",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying TraceFlag output" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $safetraceflag = 3226
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $startingtfs = $server.Query("DBCC TRACESTATUS(-1)")
            $startingtfscount = $startingtfs.Count

            if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
                $server.Query("DBCC TRACEON($safetraceflag,-1) WITH NO_INFOMSGS")
                $startingtfscount++
            }
        }

        AfterAll {
            if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
                $server.Query("DBCC TRACEOFF($safetraceflag,-1)")
            }
        }

        It "Has the right default properties" {
            $expectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'TraceFlag', 'Global', 'Status'
            $results = Get-DbaTraceFlag -SqlInstance $global:instance2
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results" {
            $results = Get-DbaTraceFlag -SqlInstance $global:instance2 -TraceFlag $safetraceflag
            $results.TraceFlag.Count | Should -Be 1
        }

        It "Returns following number of TFs: $startingtfscount" {
            $results = Get-DbaTraceFlag -SqlInstance $global:instance2
            $results.TraceFlag.Count | Should -Be $startingtfscount
        }
    }
}
