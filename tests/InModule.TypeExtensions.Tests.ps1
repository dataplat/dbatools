#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "InModule.TypeExtensions",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag IntegrationTests {
    # The Query and Invoke script methods of Server and Database in xml\dbatools.Types.ps1xml run through
    # the execution manager of a database, which is the connection context of the parent server and belongs
    # to the caller. SMO issues a USE and never switches back, so the methods put the database back. See #10555.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $contextDbName = "dbatoolsci_typeext_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $contextDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "The database context of the caller survives the script methods (#10555)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only a non-pooled connection can show this. SMO reopens a pooled connection at its default
            # database, which hides the leak.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "leaves the database context alone in Database.Query" {
            $null = $callerServer.Databases[$contextDbName].Query("SELECT 1")
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "leaves the database context alone in Database.Invoke" {
            $null = $callerServer.Databases[$contextDbName].Invoke("SELECT 1")
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "leaves the database context alone in Server.Query with a database" {
            $null = $callerServer.Query("SELECT 1", $contextDbName)
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "leaves the database context alone in Server.Invoke with a database" {
            $null = $callerServer.Invoke("SELECT 1", $contextDbName)
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }

        It "still runs the query in the database that was asked for" {
            $callerServer.Databases[$contextDbName].Query("SELECT DB_NAME() AS dbname").dbname | Should -Be $contextDbName
            $callerServer.Query("SELECT DB_NAME() AS dbname", $contextDbName).dbname | Should -Be $contextDbName
        }

        It "still returns every table when AllTables is used" {
            $allTables = $callerServer.Databases[$contextDbName].Query("SELECT 1 AS a; SELECT 2 AS b", $true)
            $allTables.Count | Should -Be 2
        }

        It "keeps the session, so temporary objects survive" {
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")
            $null = $callerServer.Databases[$contextDbName].Query("SELECT 1")
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }

        It "puts the database back even when the query fails" {
            { $callerServer.Databases[$contextDbName].Query("SELECT * FROM dbatoolsci_does_not_exist") } | Should -Throw
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }
    }

    Context "The database the caller was on is restored, not master (#10555)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A connection that starts out somewhere other than master. Restoring to master would pass the
            # tests above and still be wrong here.
            $msdbServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database msdb -NonPooledConnection

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $msdbServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "leaves the connection in msdb after Database.Query" {
            $null = $msdbServer.Databases[$contextDbName].Query("SELECT 1")
            $msdbServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "msdb"
        }

        It "leaves the connection in msdb after Server.Query with a database" {
            $null = $msdbServer.Query("SELECT 1", $contextDbName)
            $msdbServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "msdb"
        }
    }
}
