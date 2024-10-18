param($ModuleName = 'dbatools')

Describe "Get-DbaTraceFlag" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaTraceFlag
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have TraceFlag as a non-mandatory parameter of type System.Int32[]" {
            $CommandUnderTest | Should -HaveParameter TraceFlag -Type System.Int32[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
