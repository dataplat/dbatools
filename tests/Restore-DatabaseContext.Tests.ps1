#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Restore-DatabaseContext",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Server",
                "Database"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Restore-DatabaseContext is the private function that puts the current database of a connection back
    # where the caller had it, for the commands that cannot avoid moving it. See #10555.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $contextDbName = "dbatoolsci_restorectx_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $contextDbName

        # A name with a closing bracket in it, so that the escaping of the USE statement is tested against a
        # database that really exists. New-DbaDatabase would build the CREATE DATABASE statement itself, so
        # the name is created here with the escaping written out.
        $bracketDbName = "dbatoolsci_br]acket_$(Get-Random)"
        $escapedBracketDbName = $bracketDbName.Replace("]", "]]")
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "CREATE DATABASE [$escapedBracketDbName]"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName, $bracketDbName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Putting the database of the caller back" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

            # Moving the connection the way SMO does, for the tests that are about the restore rather than
            # about what moved it. Only the first test below moves it by enumerating a collection, because
            # SMO caches a collection once it is populated and a second enumeration never reaches the
            # server - so that is a fixture that works exactly once per connection.
            $moveTheConnection = {
                $null = $callerServer.ConnectionContext.ExecuteNonQuery("USE [$contextDbName]")
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterEach {
            # Every test starts from master, whatever the test before it did to the connection.
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("USE [master]")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "puts the database back after a database level collection moved the connection" {
            # Enumerating a collection of a Database object is one of the ways the context moves, and the
            # one that no script method can cover, so it is what the helper exists for.
            $null = $callerServer.Databases[$contextDbName].Users.Count
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $contextDbName

            Restore-DatabaseContext -Server $callerServer -Database "master"

            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "escapes a closing bracket in the name of the database it goes back to" {
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("USE [$escapedBracketDbName]")
            $callerDatabase = $callerServer.ConnectionContext.CurrentDatabase
            $callerDatabase | Should -Be $bracketDbName

            & $moveTheConnection
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $contextDbName

            Restore-DatabaseContext -Server $callerServer -Database $callerDatabase

            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $bracketDbName
        }

        It "does nothing when no database was remembered" {
            # A command passes what it managed to read, and reading it can come back empty. That must not
            # move a connection that nothing asked to be moved.
            & $moveTheConnection

            Restore-DatabaseContext -Server $callerServer -Database ""

            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $contextDbName
        }

        It "warns instead of throwing when the database cannot be reached" {
            # The database of the caller can be gone by the time the command is done with it - dropped,
            # renamed, taken offline, access revoked. Housekeeping must not replace the outcome of the
            # command that called it, so this warns and returns.
            & $moveTheConnection

            $missingDatabase = "dbatoolsci_does_not_exist_$(Get-Random)"

            $splatRestore = @{
                Server          = $callerServer
                Database        = $missingDatabase
                WarningVariable = "restoreWarning"
                WarningAction   = "SilentlyContinue"
            }

            # Called directly and not inside a { } | Should -Not -Throw, because -WarningVariable fills
            # the variable in the scope the command runs in and a scriptblock would take it with it. A
            # terminating error fails this test on its own, which is what the assertion would have been.
            Restore-DatabaseContext @splatRestore

            $restoreWarning -join " " | Should -BeLike "*could not be restored*"

            # The connection stays where it was, because there was nowhere to put it back to.
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $contextDbName
        }

        It "leaves the connection open and on the session of the caller" {
            # A restore that reconnected instead of running on the connection would lose everything the
            # session holds, which is the reason this is not done with a copied connection context.
            $callerSpid = $callerServer.ConnectionContext.ExecuteScalar("SELECT @@SPID")
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            & $moveTheConnection

            Restore-DatabaseContext -Server $callerServer -Database "master"

            $callerServer.ConnectionContext.ExecuteScalar("SELECT @@SPID") | Should -Be $callerSpid
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }
}
