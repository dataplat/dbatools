#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Enable-DbaTraceFlag" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaTraceFlag
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

Describe "Enable-DbaTraceFlag" -Tag "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $safeTraceFlag = 3226
        $startingTraceFlags = Get-DbaTraceFlag -SqlInstance $TestConfig.instance2

        if ($startingTraceFlags.TraceFlag -contains $safeTraceFlag) {
            $instance.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
        }
    }

    AfterAll {
        if ($startingTraceFlags.TraceFlag -notcontains $safeTraceFlag) {
            $instance.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
        }
    }

    Context "When enabling a trace flag" {
        BeforeAll {
            $results = Enable-DbaTraceFlag -SqlInstance $instance -TraceFlag $safeTraceFlag
        }

        It "Should enable the specified trace flag" {
            $results.TraceFlag -contains $safeTraceFlag | Should -BeTrue
        }
    }
}
