#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Move-DbaRegServerGroup",
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
                "Group",
                "NewGroup",
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

        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

        $group2 = "dbatoolsci-group1a"
        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group2

        $group3 = "dbatoolsci-group1b"
        $newGroup3 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group3

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $regSrvName | Remove-DbaRegServer -ErrorAction SilentlyContinue
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $group, $group2, $group3 | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When moving registered server groups" {
        It "moves a piped group" {
            $results = $newGroup2, $newGroup3 | Move-DbaRegServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name, $newGroup.Name
        }

        It "moves a manually specified group" {
            $results = Move-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group "$group\$group3" -NewGroup Default
            $results.Parent.Name | Should -Be "DatabaseEngineServerGroup"
        }
    }

    Context "The connection of the caller is left alone (#10572)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $callerGroupName = "dbatoolsci-caller-group"
            $callerTargetName = "dbatoolsci-caller-target"
            $null = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $callerGroupName
            $null = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $callerTargetName

            # Only a non-pooled connection can show this. SMO silently reopens a pooled connection, so the test
            # would pass even with the disconnect this is about.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

            # The marker is created after the lookup on purpose, because Get-DbaRegServerGroup closes the
            # connection too. This test has to measure the command under test, not its input.
            $callerInputObject = Get-DbaRegServerGroup -SqlInstance $callerServer -Group $callerGroupName
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $callerResult = Move-DbaRegServerGroup -InputObject $callerInputObject -NewGroup $callerTargetName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $callerTargetName | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still moves the group" {
            $callerResult.Parent.Name | Should -Be $callerTargetName
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }
}