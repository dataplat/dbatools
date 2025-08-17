#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDbDuplicateIndex",
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
                "IncludeOverlapping",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set up test database and table with duplicate indexes
        $dbName = "dbatools_dupeindex"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $sql = "create database [$dbName]"
        $server.Query($sql)
        $sql = "CREATE TABLE [$dbName].[dbo].[WABehaviorEvent](
                [BehaviorEventId] [smallint] NOT NULL,
                [ClickType] [nvarchar](50) NOT NULL,
                [Description] [nvarchar](512) NOT NULL,
                [BehaviorClassId] [tinyint] NOT NULL,
             CONSTRAINT [PK_WABehaviorEvent_BehaviorEventId] PRIMARY KEY CLUSTERED
            (
                [BehaviorEventId] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
            UNIQUE NONCLUSTERED
            (
                [ClickType] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
            ) ON [PRIMARY]


            CREATE UNIQUE NONCLUSTERED INDEX [IX_WABehaviorEvent_ClickType] ON [$dbName].[dbo].[WABehaviorEvent]
            (
                [ClickType] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

            ALTER TABLE [$dbName].[dbo].[WABehaviorEvent] ADD UNIQUE NONCLUSTERED
            (
                [ClickType] ASC
            )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
            "
        $server.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup test database
        $splatRemove = @{
            SqlInstance = $TestConfig.instance1
            Database    = "dbatools_dupeindex"
            Confirm     = $false
        }
        Remove-DbaDatabase @splatRemove -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Gets back some results" {
        It "return at least two results" {
            $splatFind = @{
                SqlInstance = $TestConfig.instance1
                Database    = "dbatools_dupeindex"
            }
            $results = @(Find-DbaDbDuplicateIndex @splatFind)
            $results.Status.Count | Should -BeGreaterOrEqual 2
        }
    }
}