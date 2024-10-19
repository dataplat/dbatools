param($ModuleName = 'dbatools')

Describe "Get-DbaTrace" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $traceconfig = Get-DbaSpConfigure -SqlInstance $global:instance2 -ConfigName DefaultTraceEnabled

        if ($traceconfig.RunningValue -eq $false) {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Id",
                "Default",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Test Check Default Trace" {
        BeforeAll {
            $results = Get-DbaTrace -SqlInstance $global:instance2
        }
        It "Should find at least one trace file" {
            $results.Id.Count | Should -BeGreaterThan 0
        }
    }
}
