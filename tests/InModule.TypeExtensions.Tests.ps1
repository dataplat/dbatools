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
    BeforeDiscovery {
        # Two databases whose names differ only in case can only exist on an instance with a case sensitive
        # collation, and that is the only place where a case insensitive comparison in the restore can be
        # caught. The collation decides it, not the version, so this is asked of the instance rather than
        # assumed. On a case insensitive instance the scenario cannot be built at all and the Context skips.
        $caseDiscoveryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        # Asked as a behaviour rather than matched against the collation name. The _BIN and _BIN2
        # collations are case sensitive too and carry no _CS_, so a name match would skip this whole
        # scenario on a binary collation instance. Comparing a name in sys.databases asks the exact
        # question instead, because that column carries the collation of the instance - the one that
        # database names are compared with. DB_NAME(1) is master, so the comparison needs no string
        # literal of its own.
        $caseProbeQuery = "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = UPPER(DB_NAME(1))) THEN 0 ELSE 1 END"
        $instanceIsCaseSensitive = [bool]$caseDiscoveryServer.ConnectionContext.ExecuteScalar($caseProbeQuery)
        $null = $caseDiscoveryServer | Disconnect-DbaInstance
    }

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

        It "runs on the session of the caller and not on a copy of the connection" {
            # Checking the temporary table through the caller afterwards proves nothing: it never left the
            # caller's session, so a copied connection context would pass that too. The wrapper itself has
            # to see the table, and its SPID has to be the caller's. ConnectionContext.Copy() plus
            # GetDatabaseConnection() was the other candidate for this fix and fails both assertions.
            $callerSpid = $callerServer.ConnectionContext.ExecuteScalar("SELECT @@SPID")
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $wrapperResult = $callerServer.Databases[$contextDbName].Query("SELECT @@SPID AS spid, (SELECT COUNT(*) FROM #dbatoolsci_marker) AS marker")

            $wrapperResult.spid | Should -Be $callerSpid
            $wrapperResult.marker | Should -Be 0
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

    Context "A failing restore does not become the outcome of the call (#10555)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # One database and one connection per test. The scenario is spent once it has run: the restore
            # fails because the previous database went offline, so the connection is left in master, and a
            # second call from the same connection would have master as its previous database and restore
            # it without trouble.
            $offlineDbName = "dbatoolsci_typeext_offline_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineDbName
            $offlineServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -NonPooledConnection

            $offlineStopDbName = "dbatoolsci_typeext_offlinestop_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $offlineStopDbName
            $offlineStopServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database $offlineStopDbName -NonPooledConnection

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $offlineServer, $offlineStopServer | Disconnect-DbaInstance
            foreach ($offlineDatabase in $offlineDbName, $offlineStopDbName) {
                $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDatabase -Online -Force -ErrorAction SilentlyContinue
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $offlineDatabase -ErrorAction SilentlyContinue
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns normally when the statement made the previous database unreachable" {
            # The wrapper moves the connection to master to run this, and the USE that would put it back
            # cannot work afterwards, because by then the database it names is offline. Restoring is
            # housekeeping and must not turn a statement that succeeded into an exception: a caller reading
            # that as "it did not run" might well run it a second time. The wrapper warns instead, which a
            # script method can only write to the host, so the preference is set rather than captured.
            $WarningPreference = "SilentlyContinue"
            $offlineStatement = "ALTER DATABASE [$offlineDbName] SET OFFLINE WITH ROLLBACK IMMEDIATE"

            { $offlineServer.Databases["master"].Invoke($offlineStatement) } | Should -Not -Throw

            (Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName).Status | Should -Be "OFFLINE"
        }

        It "returns normally even when the caller turned warnings into terminating errors" {
            # The same scenario with $WarningPreference = Stop, which is the one setting that can hand the
            # outcome of the call back to the housekeeping after all: Write-Warning obeys the preference of
            # the caller, and Stop makes it throw. The statement would have succeeded and the caller would
            # still see an exception - and where the statement itself failed, that exception would replace
            # its error. The wrapper neutralises the preference for its own warning, so this returns.
            # The test above still proves that a caller asking for silence gets silence, which is why the
            # preference is not simply forced to Continue.
            $WarningPreference = "Stop"
            $offlineStatement = "ALTER DATABASE [$offlineStopDbName] SET OFFLINE WITH ROLLBACK IMMEDIATE"

            # Unlike the test above, the caller has not asked for silence here, so the warning is written -
            # and it cannot be asserted on, because a script method writes to the host and neither
            # -WarningVariable nor a redirection inside the method can reach it. It is merged into the
            # output stream so that it does not land in the run, where the harness reads every warning as
            # a defect. That does not soften the test: a preference of Stop throws before anything is
            # written at all, which is how this fails against the unguarded code.
            { $null = $offlineStopServer.Databases["master"].Invoke($offlineStatement) 3>&1 } | Should -Not -Throw

            (Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineStopDbName).Status | Should -Be "OFFLINE"
        }
    }

    Context "Databases whose names differ only in case are told apart (#10579)" -Skip:(-not $instanceIsCaseSensitive) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $caseSuffix = Get-Random
            $caseDbMixed = "dbatoolsci_CaseCtx$caseSuffix"
            $caseDbLower = "dbatoolsci_casectx$caseSuffix"

            # The two names may differ only in case, but their files may not: NTFS is case insensitive, so
            # names derived from the database name collide, first the mdf and then the ldf. So the second
            # database is created under a name of its own and renamed afterwards, which keeps its files
            # apart and needs no explicit file paths.
            $caseDbTemporary = "dbatoolsci_casetmp$caseSuffix"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $caseDbMixed
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $caseDbTemporary
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "ALTER DATABASE [$caseDbTemporary] MODIFY NAME = [$caseDbLower]"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($caseDbName in $caseDbMixed, $caseDbLower, $caseDbTemporary) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $caseDbName -ErrorAction SilentlyContinue
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "restores the database of the caller when the two names differ only in case" {
            # A case insensitive comparison reports the two as equal and skips the restore, so the caller is
            # left in the wrong database - the very leak this change is about, on a valid configuration.
            $caseCaller = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database $caseDbMixed -NonPooledConnection
            try {
                $null = $caseCaller.Databases[$caseDbLower].Query("SELECT 1")

                $caseCaller.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -BeExactly $caseDbMixed
            } finally {
                $null = $caseCaller | Disconnect-DbaInstance
            }
        }
    }
}
