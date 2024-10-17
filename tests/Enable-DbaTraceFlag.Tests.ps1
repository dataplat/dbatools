param($ModuleName = 'dbatools')

Describe "Enable-DbaTraceFlag" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaTraceFlag
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have TraceFlag as a parameter" {
            $CommandUnderTest | Should -HaveParameter TraceFlag -Type Int32[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
