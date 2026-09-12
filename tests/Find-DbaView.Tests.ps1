#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaView",
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
                "Pattern",
                "IncludeSystemObjects",
                "IncludeSystemDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    Context "Command finds Views in a System Database" {
        BeforeAll {
            $ServerView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "master" -Query $ServerView
        }

        AfterAll {
            $DropView = "DROP VIEW dbo.v_dbatoolsci_sysadmin;"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "master" -Query $DropView
        }

        BeforeEach {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -IncludeSystemDatabases
        }

        It "Should find a specific View named v_dbatoolsci_sysadmin" {
            $results.Name | Should -Be "v_dbatoolsci_sysadmin"
        }

        It "Should find v_dbatoolsci_sysadmin in master" {
            $results.Database | Should -Be "master"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master).ID
        }
    }

    Context "Command finds View in a User Database" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "dbatoolsci_viewdb"
            $DatabaseView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewdb" -Query $DatabaseView
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewdb"
        }

        It "Should find a specific view named v_dbatoolsci_sysadmin" {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -Database "dbatoolsci_viewdb"
            $results.Name | Should -Be "v_dbatoolsci_sysadmin"
        }

        It "Should find v_dbatoolsci_sysadmin in dbatoolsci_viewdb Database" {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -Database "dbatoolsci_viewdb"
            $results.Database | Should -Be "dbatoolsci_viewdb"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_viewdb).ID
        }

        It "Should find no results when Excluding dbatoolsci_viewdb" {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -ExcludeDatabase "dbatoolsci_viewdb"
            $results | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connection of the caller is left in the database it was in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_view_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $contextDbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -Query "CREATE TABLE dbo.dbatoolsci_table (id INT); EXEC ('CREATE VIEW dbo.dbatoolsci_view AS SELECT id FROM dbo.dbatoolsci_table');"

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $contextBefore = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $contextResult = Find-DbaView -SqlInstance $callerServer -Database $contextDbName -Pattern dbatoolsci

            $contextAfter = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $contextDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still returns what it was asked for" {
            # Only a call that really runs can move the connection, so a command that returned nothing
            # would pass the assertion below for the wrong reason.
            $contextResult | Should -Not -BeNullOrEmpty
        }

        It "leaves the connection in the database it was in" {
            $contextAfter | Should -Be $contextBefore
        }
    }
}
