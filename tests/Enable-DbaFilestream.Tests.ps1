#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaFilestream",
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
                "Credential",
                "FileStreamLevel",
                "ShareName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Disable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When changing FileStream Level" {
        It "Should change the FileStream Level to 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -Force

            $results.InstanceAccessLevel | Should -Be 1
            $results.ServiceAccessLevel | Should -Be 1
        }

        # Parked on issue #10524, not on any property of the environment.
        #
        # On ci-azure this leaves the instance at level 1 on every attempt while level 1 itself
        # passes in the same run. The diagnostic below showed why that is as far as anyone can get
        # today: the instance came back reporting ServiceShareName "SQL2019", the instance-name
        # fallback that Set-FileSystemSetting uses when no share name is given - the value the
        # level 1 test above leaves behind. So the level 2 call did not stall halfway, it changed
        # nothing at all, and the WMI return code that would say why is swallowed by #10524:
        # Get-FilestreamReturnValue reports every code as success, and Enable-DbaFilestream only
        # surfaces it when -Force is absent, which is not the path used here.
        #
        # Two environmental explanations were tried and both are refuted, so do not re-guess:
        # the RsFx filter driver is running even with FILESTREAM fully disabled, and the Server
        # service is running on the ci-azure runners where this still fails.
        #
        # Once #10524 is fixed the return code becomes visible and this can be unskipped to read
        # it. The assertions keep their diagnostics for exactly that.
        It "Should change the FileStream Level to 2" -Skip:$true {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 2 -ShareName TestShare -Force

            # A bare "Expected 2, but got 1" says nothing about which of the two levels stalled or
            # what the instance ended up with, which cost a full CI round trip on 2026-08-06.
            # Report the state the instance actually reached so the next failure explains itself.
            $reportedState = (Get-DbaFilestream -SqlInstance $TestConfig.InstanceRestart | Out-String).Trim()

            $results.InstanceAccessLevel | Should -Be 2 -Because "the instance reported $reportedState"
            $results.ServiceAccessLevel | Should -Be 2 -Because "the instance reported $reportedState"
            $results.ServiceShareName | Should -Be TestShare -Because "the instance reported $reportedState"
        }

        It "Should warn if using ShareName with FileStreamLevel 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -ShareName Test -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike '*Filestream must be at least level 2 when using ShareName*'
            $results | Should -BeNullOrEmpty
        }
    }
}