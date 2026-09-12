#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbUpgrade",
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
                "ExcludeDatabase",
                "NoCheckDb",
                "NoUpdateUsage",
                "NoUpdateStats",
                "NoRefreshView",
                "AllUserDatabases",
                "Force",
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

        $setupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # The command skips a database that is already at the compatibility level of the instance, so the
        # test database is created one level below it. The level is asked of the instance instead of being
        # hardcoded: every supported version accepts the level of the major version before it.
        $instanceCompatibility = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($setupServer.VersionMajor)0"
        $previousCompatibility = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($setupServer.VersionMajor - 1)0"

        $upgradeDbName = "dbatoolsci_upgrade_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $setupServer -Name $upgradeDbName
        $null = Set-DbaDbCompatibility -SqlInstance $setupServer -Database $upgradeDbName -Compatibility $previousCompatibility

        # sp_refreshview only runs for a user view, so without one the fourth statement of the command
        # would never execute and could not show whether it moves the connection.
        $splatCreateView = @{
            SqlInstance = $setupServer
            Database    = $upgradeDbName
            Query       = "CREATE TABLE dbo.dbatoolsci_table (id INT); EXEC ('CREATE VIEW dbo.dbatoolsci_view AS SELECT id FROM dbo.dbatoolsci_table');"
        }
        $null = Invoke-DbaQuery @splatCreateView

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $setupServer -Database $upgradeDbName -ErrorAction SilentlyContinue
        $null = $setupServer | Disconnect-DbaInstance

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Upgrading a database leaves the connection of the caller alone (#10556)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which wipes the leak before it can be read.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $contextBefore = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $upgradeResult = Invoke-DbaDbUpgrade -SqlInstance $callerServer -Database $upgradeDbName

            $contextAfter = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "upgrades the database to the compatibility level of the instance" {
            $upgradeResult.OriginalCompatibility | Should -Be $previousCompatibility.ToString().Replace("Version", "")
            $upgradeResult.CurrentCompatibility | Should -Be $instanceCompatibility.ToString().Replace("Version", "")
            $upgradeResult.Compatibility | Should -Be $instanceCompatibility.ToString().Replace("Version", "")
        }

        It "runs every maintenance step" {
            # Only a statement that ran can move the connection, so a command that did nothing would pass
            # the assertion below for the wrong reason.
            $upgradeResult.DataPurity | Should -Be "Success"
            $upgradeResult.UpdateUsage | Should -Be "Success"
            $upgradeResult.UpdateStats | Should -Be "Success"
            $upgradeResult.RefreshViews | Should -Be "Success"
        }

        It "leaves the connection in the database it was in" {
            $contextAfter | Should -Be $contextBefore
        }

        It "does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }
    }

    Context "The database the caller was in is restored, not master (#10555)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $tempdbCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database tempdb -NonPooledConnection

            # The database is at the level of the instance by now, so only -Force makes the maintenance
            # statements run again. A fix that put the connection back to master instead of back to what
            # the caller had would pass every assertion of the context above and fail here.
            $forcedResult = Invoke-DbaDbUpgrade -SqlInstance $tempdbCallerServer -Database $upgradeDbName -Force

            $tempdbContextAfter = $tempdbCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $tempdbCallerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "runs the maintenance steps again" {
            $forcedResult.DataPurity | Should -Be "Success"
            $forcedResult.UpdateUsage | Should -Be "Success"
            $forcedResult.UpdateStats | Should -Be "Success"
            $forcedResult.RefreshViews | Should -Be "Success"
        }

        It "leaves the connection in tempdb" {
            $tempdbContextAfter | Should -Be "tempdb"
        }
    }

    Context "The maintenance statements put the database back themselves (#10556)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $statementCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $statementContextBefore = $statementCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # -NoRefreshView is the case the restore around the view enumeration cannot cover, because with
            # it the command never enumerates the views. Whatever the DBCC and stored procedure statements
            # do to the connection has to be undone by the statements themselves.
            $statementResult = Invoke-DbaDbUpgrade -SqlInstance $statementCallerServer -Database $upgradeDbName -NoRefreshView -Force

            $statementContextAfter = $statementCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $statementCallerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "runs the statements it was not told to skip" {
            $statementResult.DataPurity | Should -Be "Success"
            $statementResult.UpdateUsage | Should -Be "Success"
            $statementResult.UpdateStats | Should -Be "Success"
            $statementResult.RefreshViews | Should -Be "Skipped"
        }

        It "leaves the connection in the database it was in" {
            $statementContextAfter | Should -Be $statementContextBefore
        }
    }
}
