#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaMaintenanceSolution",
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
                "Solution",
                "LocalFile",
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

        $databaseName = "dbatoolsci_maintenance_update_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $databaseName

        $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "sql-server-maintenance-solution-main"
        Remove-Item -Path $localCachedCopy -Recurse -Force -ErrorAction SilentlyContinue

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $databaseName
        Remove-Item -Path $localCachedCopy -Recurse -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "The update runs in the named database and the connection of the caller is left alone (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Own database, so that the expectations of the other tests about $databaseName still hold.
            $contextDbName = "dbatoolsci_maintenance_context_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $contextDbName

            # A stub of the procedure, so that the command sees it as installed and takes the update path.
            $splatStub = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $contextDbName
                Query       = "CREATE PROCEDURE dbo.CommandExecute AS SELECT 1"
            }
            $null = Invoke-DbaQuery @splatStub

            # Remember whether master already has one, so that the cleanup cannot remove a real installation.
            $splatMasterBefore = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Database     = "master"
                Query        = "SELECT COUNT(*) FROM sys.procedures WHERE name = @procName"
                SqlParameter = @{ procName = "CommandExecute" }
                As           = "SingleValue"
            }
            $masterHadProcedure = (Invoke-DbaQuery @splatMasterBefore) -gt 0

            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $splatUpdate = @{
                SqlInstance = $callerServer
                Database    = $contextDbName
                Solution    = "CommandExecute"
            }
            $updateResult = Update-DbaMaintenanceSolution @splatUpdate

            $splatUpdatedDefinition = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Database     = $contextDbName
                Query        = "SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(@procName)"
                SqlParameter = @{ procName = "dbo.CommandExecute" }
                As           = "SingleValue"
            }
            $updatedDefinition = Invoke-DbaQuery @splatUpdatedDefinition

            $masterHasProcedureNow = (Invoke-DbaQuery @splatMasterBefore) -gt 0

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName

            if (-not $masterHadProcedure -and $masterHasProcedureNow) {
                $splatCleanupMaster = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Database    = "master"
                    Query       = "DROP PROCEDURE dbo.CommandExecute"
                }
                $null = Invoke-DbaQuery @splatCleanupMaster
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "reports the procedure as updated" {
            $updateResult.IsUpdated | Should -BeTrue
        }

        It "updates the procedure in the database that was named" {
            $updatedDefinition | Should -Match "@DatabaseContext"
        }

        It "does not create the procedure in the database the connection is on" {
            $masterHasProcedureNow | Should -Be $masterHadProcedure
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }

        It "leaves the connection in the database it was on" {
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }
    }

    It "downloads the current GitHub source before checking installed procedures" {
        $results = Update-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceSingle -Database $databaseName -Solution CommandExecute -Force -EnableException -WarningAction SilentlyContinue

        $results | Should -HaveCount 1
        $results.Procedure | Should -Be "CommandExecute"
        $results.IsUpdated | Should -BeFalse
        $results.Results | Should -Be "Procedure not installed"
        Get-ChildItem -Path $localCachedCopy -Recurse -Filter "CommandExecute.sql" | Should -Not -BeNullOrEmpty
        $WarnVar | Should -Match "Force still suppresses confirmation prompts"
    }
}

