param($ModuleName = 'dbatools')

Describe "Enable-DbaTraceFlag" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaTraceFlag
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have TraceFlag as a parameter" {
            $CommandUnderTest | Should -HaveParameter TraceFlag -Type System.Int32[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Verifying TraceFlag output" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $startingtfs = Get-DbaTraceFlag -SqlInstance $global:instance2
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

        It "Should enable trace flag $safetraceflag" {
            $results = Enable-DbaTraceFlag -SqlInstance $server -TraceFlag $safetraceflag
            $results.TraceFlag | Should -Contain $safetraceflag
        }
    }
}
