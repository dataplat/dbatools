$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'TraceFlag', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying TraceFlag output" {
        BeforeAll {
            $safetraceflag = 3226
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $startingtfs = $server.Query("DBCC TRACESTATUS(-1)")
            $startingtfscount = $startingtfs.Count

            if ($startingtfs.TraceFlag -notcontains $safetraceflag) {
                $server.Query("DBCC TRACEON($safetraceflag,-1)  WITH NO_INFOMSGS")
                $startingtfscount++
            }
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

        It "Returns filtered results" {
            $results = Get-DbaTraceFlag -SqlInstance $script:instance2 -TraceFlag $safetraceflag
            $results.TraceFlag.Count | Should Be 1
        }
        It "Returns following number of TFs: $startingtfscount" {
            $results = Get-DbaTraceFlag -SqlInstance $script:instance2
            $results.TraceFlag.Count | Should Be $startingtfscount
        }
    }
}