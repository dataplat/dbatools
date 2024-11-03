#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Disable-DbaTraceFlag" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Disable-DbaTraceFlag
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "TraceFlag",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasParams = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasParams | Should -BeNullOrEmpty
        }
    }
}

Describe "Disable-DbaTraceFlag" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $startingTraceFlags = Get-DbaTraceFlag -SqlInstance $server
        $safeTraceFlag = 3226

        if ($startingTraceFlags.TraceFlag -notcontains $safeTraceFlag) {
            $null = $server.Query("DBCC TRACEON($safeTraceFlag,-1)")
        }
    }

    AfterAll {
        if ($startingTraceFlags.TraceFlag -contains $safeTraceFlag) {
            $server.Query("DBCC TRACEON($safeTraceFlag,-1) WITH NO_INFOMSGS")
        }
    }

    Context "When disabling trace flags" {
        BeforeAll {
            $results = Disable-DbaTraceFlag -SqlInstance $server -TraceFlag $safeTraceFlag
        }

        It "Should disable trace flag $safeTraceFlag" {
            $results.TraceFlag | Should -Contain $safeTraceFlag
        }
    }
}
