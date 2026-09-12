#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaRegServer",
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
                "ServerName",
                "Name",
                "Description",
                "Group",
                "ActiveDirectoryTenant",
                "ActiveDirectoryUserId",
                "ConnectionString",
                "OtherParams",
                "InputObject",
                "ServerObject",
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
        $groupobject = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Remove-DbaRegServerGroup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a registered server" {
        BeforeAll {
            $results1 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName
        }

        It "Adds a registered server with correct name" {
            $results1.Name | Should -Be $srvName
        }

        It "Adds a registered server with correct server name" {
            $results1.ServerName | Should -Be $srvName
        }

        It "Adds a registered server with non-null SqlInstance" {
            $results1.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "When adding a registered server with extended properties" {
        BeforeAll {
            $splatRegServer = @{
                SqlInstance = $TestConfig.InstanceSingle
                ServerName  = $regSrvName
                Name        = $srvName
                Group       = $groupobject
                Description = $regSrvDesc
            }

            $results2 = Add-DbaRegServer @splatRegServer
        }

        It "Adds a registered server with correct server name" {
            $results2.ServerName | Should -Be $regSrvName
        }

        It "Adds a registered server with correct description" {
            $results2.Description | Should -Be $regSrvDesc
        }

        It "Adds a registered server with correct name" {
            $results2.Name | Should -Be $srvName
        }

        It "Adds a registered server with non-null SqlInstance" {
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "When adding registered servers repeatedly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command used to reconnect the store connection for its verification call and never
            # close it again, one new sleeping session per call. Count sessions through a server object
            # opened once, because a per-call counting command would open connections of its own.
            $countServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $countQuery = @"
select count(*)
from sys.dm_exec_sessions
where program_name like 'dbatools%'
  and status = 'sleeping'
  and session_id <> @@spid
"@

            # One warm-up call so the shared pooled connection exists before the baseline is taken.
            $null = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName "dbatoolsci-leak0" -Name "dbatoolsci-leak0"
            $sleepingBefore = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $null = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName "dbatoolsci-leak$i" -Name "dbatoolsci-leak$i"
            }
            $sleepingAfter = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            # Early pipeline termination stops the command right after the emitted verification
            # object - only a buffered emission with the disconnect in a finally survives that.
            foreach ($i in 4..6) {
                $null = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName "dbatoolsci-leak$i" -Name "dbatoolsci-leak$i" | Select-Object -First 1
            }
            $sleepingAfterEarlyEnd = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Like "dbatoolsci-leak*" | Remove-DbaRegServer
            $countServer.ConnectionContext.Disconnect()

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Leaves no sleeping session behind" {
            $sleepingAfter | Should -Be $sleepingBefore
        }

        It "Leaves no sleeping session behind when the pipeline ends early" {
            $sleepingAfterEarlyEnd | Should -Be $sleepingBefore
        }
    }
}