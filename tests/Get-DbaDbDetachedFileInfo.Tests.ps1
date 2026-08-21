#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbDetachedFileInfo",
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
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $versionName = $server.GetSqlServerVersionName()
        $random = Get-Random
        $dbname = "dbatoolsci_detatch_$random"
        $server.Query("CREATE DATABASE $dbname")
        $path = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Where-Object PhysicalName -like "*.mdf").PhysicalName
        # Remembered before the database is detached, so that the collation the command resolves can be
        # compared against the real one. The command falls back to the numeric collation id when the lookup
        # fails, and that is not null either, so only an exact comparison can tell the two apart.
        $expectedCollation = $server.Databases[$dbname].Collation
        Detach-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Force
    }

    AfterAll {
        $server.Query("CREATE DATABASE $dbname
            ON (FILENAME = '$path')
            FOR ATTACH")
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $TestConfig.InstanceSingle -Path $path
        }

        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be created database" {
            $results.Name | Should -Be $dbname
        }

        It "Should be the correct version" {
            $results.Version | Should -Be $versionName
        }

        It "Should have Data files" {
            $results.DataFiles | Should -Not -BeNullOrEmpty
        }

        It "Should have Log files" {
            $results.LogFiles | Should -Not -BeNullOrEmpty
        }
    }

    Context "The connection of the caller keeps its database (#10555)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The collation lookup used to run through the master database, which leaves the connection of
            # the caller there. Only a non-pooled connection shows it, because SMO reopens a pooled one at
            # its default database.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database msdb -NonPooledConnection
            $callerResult = Get-DbaDbDetachedFileInfo -SqlInstance $callerServer -Path $path

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still reads the detached file" {
            $callerResult.Name | Should -Be $dbname
        }

        It "still resolves the collation to its name" {
            # Not just "not empty": the command catches every failure of the lookup and falls back to the
            # numeric collation id, which is not empty either, so this assertion would pass even if the
            # changed call always threw.
            $callerResult.Collation | Should -Be $expectedCollation
        }

        It "leaves the connection in the database it was on" {
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "msdb"
        }
    }
}