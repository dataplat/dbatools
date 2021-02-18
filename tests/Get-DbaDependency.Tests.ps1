$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            [object[]]$knownParameters = 'InputObject', 'AllowSystemObjects', 'Parents', 'IncludeSelf', 'EnableException'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname

        $createTableScript = "IF OBJECT_ID('dbo.dbatoolsci_nodependencies') IS NOT NULL
                            BEGIN
                                DROP TABLE dbo.dbatoolsci_nodependencies;
                            END

                            IF OBJECT_ID('dbo.dbatoolsci3') IS NOT NULL
                            BEGIN
                                DROP TABLE dbo.dbatoolsci3;
                            END

                            IF OBJECT_ID('dbo.dbatoolsci2') IS NOT NULL
                            BEGIN
                                DROP TABLE dbo.dbatoolsci2;
                            END

                            IF OBJECT_ID('dbo.dbatoolsci1') IS NOT NULL
                            BEGIN
                                DROP TABLE dbo.dbatoolsci1;
                            END

                            CREATE TABLE dbo.dbatoolsci_nodependencies
                            (
                                ID INTEGER
                            );

                            CREATE TABLE dbo.dbatoolsci1
                            (
                                ID INTEGER PRIMARY KEY
                            );

                            CREATE TABLE dbo.dbatoolsci2
                            (
                                ID INTEGER PRIMARY KEY
                            ,    ParentID INTEGER FOREIGN KEY REFERENCES dbo.dbatoolsci1(ID)
                            );

                            CREATE TABLE dbo.dbatoolsci3
                            (
                                ID INTEGER
                            ,    ParentID INTEGER FOREIGN KEY REFERENCES dbo.dbatoolsci2(ID)
                            );

                            CREATE TABLE [dbo].[TableA](
                                [TableAId] [int] NOT NULL,
                                [TableBId] [int] NULL,
                             CONSTRAINT [PK_TableA] PRIMARY KEY CLUSTERED
                            (
                                [TableAId] ASC
                            ));

                            CREATE TABLE [dbo].[TableB](
                                [TableBId] [int] NOT NULL,
                                [TableAId] [int] NOT NULL,
                             CONSTRAINT [PK_TableB] PRIMARY KEY CLUSTERED
                            (
                                [TableBId] ASC
                            ));

                            ALTER TABLE [dbo].[TableA]  WITH CHECK ADD  CONSTRAINT [FK_TableA_TableB] FOREIGN KEY([TableBId])
                            REFERENCES [dbo].[TableB] ([TableBId]);

                            ALTER TABLE [dbo].[TableA] CHECK CONSTRAINT [FK_TableA_TableB];

                            ALTER TABLE [dbo].[TableB]  WITH CHECK ADD  CONSTRAINT [FK_TableB_TableA] FOREIGN KEY([TableAId])
                            REFERENCES [dbo].[TableA] ([TableAId]);

                            ALTER TABLE [dbo].[TableB] CHECK CONSTRAINT [FK_TableB_TableA];
                            "


        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Database $dbname -Query $createTableScript
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }

    It "Test with a table that has no dependencies" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci_nodependencies | Get-DbaDependency -Parents
        $results.length | Should -Be 0
    }

    It "Test with a table that has parent dependencies" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci2 | Get-DbaDependency -Parents
        $results.length | Should -Be 1
        $results[0].Dependent | Should -Be "dbatoolsci1"
        $results[0].Tier | Should -Be -1
    }

    It "Test with a table that has child dependencies" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci2 | Get-DbaDependency -IncludeSelf
        $results.length | Should -Be 2
        $results[1].Dependent | Should -Be "dbatoolsci3"
        $results[1].Tier | Should -Be 1
    }

    It "Test with a table that has multiple levels of dependencies and use -IncludeSelf" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci3 | Get-DbaDependency -IncludeSelf -Parents
        $results.length | Should -Be 3
        $results[0].Dependent | Should -Be "dbatoolsci1"
        $results[0].Tier | Should -Be -2
    }

    # https://github.com/sqlcollaborative/dbatools/issues/7139
    It "Test with a circular dependency" {
        $tableA = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -table TableA
        $results = $tableA | Get-DbaDependency
        $results.Count | Should -Be 2
        $results.Dependent | Should -Be ('TableB', 'TableA')
    }
}