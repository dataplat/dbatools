param($ModuleName = 'dbatools')

Describe "Disable-DbaTraceFlag" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaTraceFlag
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
            . "$PSScriptRoot\constants.ps1"
        }

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

        It "Should disable trace flag $safetraceflag" {
            $results = Disable-DbaTraceFlag -SqlInstance $server -TraceFlag $safetraceflag
            $results.TraceFlag | Should -Contain $safetraceflag
        }
    }
}
