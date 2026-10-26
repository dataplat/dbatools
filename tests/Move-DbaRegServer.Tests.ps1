#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Move-DbaRegServer",
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
                "ServerName",
                "Group",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

        $srvName2 = "dbatoolsci-server2"
        $group2 = "dbatoolsci-group1a"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group2
        $newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $regSrvName3 = "dbatoolsci-server3"
        $srvName3 = "dbatoolsci-server3"
        $regSrvDesc3 = "dbatoolsci-server3desc"

        $newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3

        $testGroupHR = "dbatoolsci-HR-$random"
        $testGroupFinance = "dbatoolsci-Finance-$random"
        $regSrvNameHR = "dbatoolsci-HR-$random"
        $regSrvNameFinance = "dbatoolsci-Finance-$random"

        $newTestGroupHR = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $testGroupHR
        $newTestGroup5 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $testGroupFinance
        $newServerHR = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvNameHR -Group $testGroupHR
        $newServerFinance = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvNameFinance -Group $testGroupHR

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $regSrvName, $regSrvName2, $regSrvName3, $regSrvNameHR, $regSrvNameFinance | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $group, $group2, $testGroupHR, $testGroupFinance | Remove-DbaRegServerGroup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "moves a piped server" {
        $results = $newServer2 | Move-DbaRegServer -NewGroup $newGroup.Name
        $results.Parent.Name | Should -Be $newGroup.Name
        $results.Name | Should -Be $regSrvName2
    }

    It "moves a manually specified server" {
        $results = Move-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName3 -NewGroup $newGroup2.Name
        $results.Parent.Name | Should -Be $newGroup2.Name
        $results.Description | Should -Be $regSrvDesc3
    }

    # see https://github.com/dataplat/dbatools/issues/7112
    It "moves a piped server to a target group" {
        $results = Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Group $testGroupHR | Move-DbaRegServer -Group $testGroupFinance
        $results.Count | Should -Be 2
    }

    Context "The connection of the caller is left alone (#10572)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $callerRegSrvName = "dbatoolsci-caller-server"
            $callerTargetName = "dbatoolsci-caller-target"
            $null = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $callerTargetName
            $null = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $callerRegSrvName -Name $callerRegSrvName

            # Only a non-pooled connection can show this. SMO silently reopens a pooled connection, so the test
            # would pass even with the disconnect this is about.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

            # The marker is created after the lookup on purpose, because Get-DbaRegServer closes the connection
            # too. This test has to measure the command under test, not its input.
            $callerInputObject = Get-DbaRegServer -SqlInstance $callerServer -Name $callerRegSrvName
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $callerResult = Move-DbaRegServer -InputObject $callerInputObject -Group $callerTargetName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $callerRegSrvName | Remove-DbaRegServer -ErrorAction SilentlyContinue
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $callerTargetName | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still moves the registered server" {
            $callerResult.Parent.Name | Should -Be $callerTargetName
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }
}