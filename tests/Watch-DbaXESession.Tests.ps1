#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Watch-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "InputObject",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Stop-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Start-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # This command is special and runs infinitely so don't actually try to run it
        It "warns if XE session is not running" {
            $results = Watch-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "system_health is not running"
        }

        It "warns once for each piped XE session that is not running" {
            $suffix = [guid]::NewGuid().ToString("N")
            $firstName = "dbatoolsci_watch_pipeline_first_$suffix"
            $secondName = "dbatoolsci_watch_pipeline_second_$suffix"
            $firstSession = New-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Name $firstName
            $secondSession = New-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Name $secondName

            $results = @($firstSession, $secondSession) | Watch-DbaXESession -WarningAction SilentlyContinue -WarningVariable warn

            $results | Should -BeNullOrEmpty
            @($warn).Count | Should -Be 2
            @($warn | Where-Object { $PSItem -match [regex]::Escape($firstName) }).Count | Should -Be 1
            @($warn | Where-Object { $PSItem -match [regex]::Escape($secondName) }).Count | Should -Be 1
        }
    }
}
