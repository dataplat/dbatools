#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaRegServerGroup",
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
                "Name",
                "InputObject",
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

        # Set variables. They are available in all the It blocks.
        $groupName1 = "dbatoolsci-group1"
        $groupName2 = "dbatoolsci-group1a"

        # Create the objects.
        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $groupName1
        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $groupName2

        $hellagroup = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Id 1 | Add-DbaRegServerGroup -Name dbatoolsci-first | Add-DbaRegServerGroup -Name dbatoolsci-second | Add-DbaRegServerGroup -Name dbatoolsci-third | Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing registered server groups" {
        It "supports dropping via the pipeline" {
            $results = $newGroup | Remove-DbaRegServerGroup
            $results.Name | Should -Be $groupName1
            $results.Status | Should -Be "Dropped"
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $groupName2
            $results.Name | Should -Be $groupName2
            $results.Status | Should -Be "Dropped"
        }

        It "supports hella long group name" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $hellagroup.Group
            $results.Name | Should -Be "dbatoolsci-third"
        }
    }

    Context "The connection of the caller is left alone (#10572)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $callerGroupName = "dbatoolsci-caller-group"
            $null = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $callerGroupName

            # Only a non-pooled connection can show this. SMO silently reopens a pooled connection, so the test
            # would pass even with the disconnect this is about.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

            # The marker is created after the lookup on purpose, because Get-DbaRegServerGroup closes the
            # connection too. This test has to measure the command under test, not its input.
            $callerInputObject = Get-DbaRegServerGroup -SqlInstance $callerServer -Group $callerGroupName
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $callerResult = Remove-DbaRegServerGroup -InputObject $callerInputObject

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still drops the group" {
            $callerResult.Status | Should -Be "Dropped"
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }
}