#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaXEReplay",
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
                "Database",
                "Event",
                "InputObject",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Skip all contexts if sqlcmd is not available
        $global:skipSqlcmd = -not (Get-Command sqlcmd -ErrorAction SilentlyContinue)

        if (-not $global:skipSqlcmd) {
            # Create mock XE event objects with a known SQL statement
            $xeMarker = "dbatoolsci_replay_$(Get-Random)"
            $mockEvent = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                statement  = "SELECT '$xeMarker' AS ReplayTest"
                batch_text = $null
            }

            # Run the replay against the test instance
            $results = @($mockEvent | Invoke-DbaXEReplay -SqlInstance $TestConfig.instance1 -OutVariable "global:dbatoolsciOutput")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $global:skipSqlcmd = $null
    }

    Context "When replaying XE events" -Skip:$global:skipSqlcmd {
        It "Should return output from replayed queries" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return string output" {
            $results[0] | Should -BeOfType [System.String]
        }

        It "Should contain the expected marker in the output" {
            $results | Should -Contain $xeMarker
        }
    }

    Context "When using -Raw parameter" -Skip:$global:skipSqlcmd {
        BeforeAll {
            $mockEventRaw = [PSCustomObject]@{
                Name       = "sql_batch_completed"
                statement  = "SELECT 'dbatoolsci_raw_test' AS RawTest"
                batch_text = $null
            }
            $rawResults = @($mockEventRaw | Invoke-DbaXEReplay -SqlInstance $TestConfig.instance1 -Raw)
        }

        It "Should return raw output" {
            $rawResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "When filtering by event type" -Skip:$global:skipSqlcmd {
        BeforeAll {
            # Create an event with a non-matching name - should be filtered out
            $nonMatchingEvent = [PSCustomObject]@{
                Name       = "wait_info"
                statement  = "SELECT 'should_not_run' AS FilterTest"
                batch_text = $null
            }
            $filteredResults = @($nonMatchingEvent | Invoke-DbaXEReplay -SqlInstance $TestConfig.instance1)
        }

        It "Should not return output for non-matching events" {
            $filteredResults | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" -Skip:$global:skipSqlcmd {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.String]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.String"
        }
    }
}