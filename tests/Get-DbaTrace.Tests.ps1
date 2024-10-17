param($ModuleName = 'dbatools')

Describe "Get-DbaTrace" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $traceconfig = Get-DbaSpConfigure -SqlInstance $env:instance2 -ConfigName DefaultTraceEnabled

        if ($traceconfig.RunningValue -eq $false) {
            $server = Connect-DbaInstance -SqlInstance $env:instance2
            $server.Query("EXEC sp_configure 'show advanced options', 1;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'default trace enabled', 1;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'show advanced options', 0;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
        }
    }

    AfterAll {
        if ($traceconfig.RunningValue -eq $false) {
            $server.Query("EXEC sp_configure 'show advanced options', 1;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'default trace enabled', 0;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'show advanced options', 0;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaTrace
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Id as a parameter" {
            $CommandUnderTest | Should -HaveParameter Id -Type Int32[]
        }
        It "Should have Default as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Default -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Test Check Default Trace" {
        BeforeAll {
            $results = Get-DbaTrace -SqlInstance $env:instance2
        }
        It "Should find at least one trace file" {
            $results.Id.Count | Should -BeGreaterThan 0
        }
    }
}
