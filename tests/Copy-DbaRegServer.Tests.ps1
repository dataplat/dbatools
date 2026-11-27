#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaRegServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Group",
                "SwitchServerName",
                "Force",
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
        $serverName = "dbatoolsci-server1"
        $groupName = "dbatoolsci-group1"
        $regServerName = "dbatoolsci-server12"
        $regServerDesc = "dbatoolsci-server123"

        # Create the objects.
        $sourceServer = Connect-DbaInstance $TestConfig.InstanceCopy2
        $regStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourceServer.ConnectionContext.SqlConnectionObject)
        $dbStore = $regStore.DatabaseEngineServerGroup

        $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($dbStore, $groupName)
        $newGroup.Create()
        $dbStore.Refresh()

        $groupStore = $dbStore.ServerGroups[$groupName]
        $newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($groupStore, $regServerName)
        $newServer.ServerName = $serverName
        $newServer.Description = $regServerDesc
        $newServer.Create()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $newGroup.Drop()
        $destServer = Connect-DbaInstance $TestConfig.InstanceCopy1
        $destRegStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destServer.ConnectionContext.SqlConnectionObject)
        $destDbStore = $destRegStore.DatabaseEngineServerGroup
        $destGroupStore = $destDbStore.ServerGroups[$groupName]
        $destGroupStore.Drop()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying registered servers" {
        It "Should complete successfully" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                CMSGroup    = $groupName
            }
            $results = Copy-DbaRegServer @splatCopy
            $results.Status | Should -Be @("Successful", "Successful")
        }
    }

    Context "When copying registered servers repeatedly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A store keeps its connection open after it was read. Count the sleeping sessions of this process through
            # server objects opened once, because a counting command would open connections of its own.
            $countSourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -NonPooledConnection
            $countDestServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -NonPooledConnection
            $countQuery = @"
SELECT COUNT(*)
FROM sys.dm_exec_sessions
WHERE host_process_id = $PID
  AND status = N'sleeping'
  AND session_id <> @@SPID
"@
            $splatRepeat = @{
                Source      = $TestConfig.InstanceCopy2
                Destination = $TestConfig.InstanceCopy1
                CMSGroup    = $groupName
                Force       = $true
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # One warm-up call so the shared pooled connections exist before the baseline is taken.
            $null = Copy-DbaRegServer @splatRepeat
            $sourceSleepingBefore = $countSourceServer.ConnectionContext.ExecuteScalar($countQuery)
            $destSleepingBefore = $countDestServer.ConnectionContext.ExecuteScalar($countQuery)

            $repeatResults = foreach ($round in 1..3) {
                Copy-DbaRegServer @splatRepeat
            }
            $sourceSleepingAfter = $countSourceServer.ConnectionContext.ExecuteScalar($countQuery)
            $destSleepingAfter = $countDestServer.ConnectionContext.ExecuteScalar($countQuery)
        }

        AfterAll {
            $countSourceServer.ConnectionContext.Disconnect()
            $countDestServer.ConnectionContext.Disconnect()
        }

        It "Copies in every round" {
            $repeatResults | Where-Object Status -ne "Successful" | Should -BeNullOrEmpty
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Leaves no sleeping session behind on the source" {
            # A pooled session can end while the test runs, but a leak adds one per round.
            $sourceSleepingAfter | Should -BeLessOrEqual $sourceSleepingBefore
        }

        It "Leaves no sleeping session behind on the destination" {
            $destSleepingAfter | Should -BeLessOrEqual $destSleepingBefore
        }
    }
}