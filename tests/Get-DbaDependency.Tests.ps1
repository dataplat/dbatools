$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
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

                            IF OBJECT_ID('dbo.FK_circref_A_B') IS NOT NULL
                            BEGIN
                                ALTER TABLE dbo.dbatoolsci_circrefA ADD CONSTRAINT FK_circref_A_B FOREIGN KEY(BID) REFERENCES dbo.dbatoolsci_circrefB (ID)
                            END

                            IF OBJECT_ID('dbo.FK_circref_B_A') IS NOT NULL
                            BEGIN
                                ALTER TABLE dbo.dbatoolsci_circrefB ADD CONSTRAINT FK_circref_B_A FOREIGN KEY(AID) REFERENCES dbo.dbatoolsci_circrefA (ID)
                            END

                            IF OBJECT_ID('dbo.dbatoolsci_circrefA') IS NOT NULL
                            BEGIN
                                DROP TABLE dbo.dbatoolsci_circrefA;
                            END

                            IF OBJECT_ID('dbo.dbatoolsci_circrefB') IS NOT NULL
                            BEGIN
                                DROP TABLE dbo.dbatoolsci_circrefB;
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
                            ,	ParentID INTEGER FOREIGN KEY REFERENCES dbo.dbatoolsci1(ID)
                            );

                            CREATE TABLE dbo.dbatoolsci3
                            (
                                ID INTEGER
                            ,	ParentID INTEGER FOREIGN KEY REFERENCES dbo.dbatoolsci2(ID)
                            );

                            CREATE TABLE dbo.dbatoolsci_circrefA
                            (
                                ID INTEGER PRIMARY KEY
                            ,	BID INTEGER
                            );

                            CREATE TABLE dbo.dbatoolsci_circrefB
                            (
                                ID INTEGER PRIMARY KEY
                            ,	AID INTEGER
                            );

                            ALTER TABLE dbo.dbatoolsci_circrefA ADD CONSTRAINT FK_circref_A_B FOREIGN KEY(BID) REFERENCES dbo.dbatoolsci_circrefB (ID)

                            ALTER TABLE dbo.dbatoolsci_circrefB ADD CONSTRAINT FK_circref_B_A FOREIGN KEY(AID) REFERENCES dbo.dbatoolsci_circrefA (ID)

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
        $results.length         | Should -Be 1
        $results[0].Dependent   | Should -Be "dbatoolsci1"
        $results[0].Tier        | Should -Be -1
    }

    It "Test with a table that has child dependencies" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci2 | Get-DbaDependency -IncludeSelf
        $results.length | Should -Be 2
        $results[1].Dependent   | Should -Be "dbatoolsci3"
        $results[1].Tier        | Should -Be 1
    }

    It "Test with a table that has multiple levels of dependencies and use -IncludeSelf" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci3 | Get-DbaDependency -IncludeSelf -Parents
        $results.length         | Should -Be 3
        $results[0].Dependent   | Should -Be "dbatoolsci1"
        $results[0].Tier        | Should -Be -2
    }

    It "Test with a tables that have circular dependencies" {
        # this causes infinite loop when circular dependencies exist in dependency tree.
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci_circrefA | Get-DbaDependency
        $results.length | Should -Be 2
        $results[0].Dependent   | Should -Be "dbatoolsci_circrefB"
        $results[0].Tier        | Should -Be 1
        $results[1].Dependent   | Should -Be "dbatoolsci_circrefA"
        $results[1].Tier        | Should -Be 2
    }

    It "Test with a tables that have circular dependencies and use -IncludeSelf" {
        # this causes infinite loop when circular dependencies exist in dependency tree.
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table dbo.dbatoolsci_circrefA | Get-DbaDependency -IncludeSelf
        $results.length | Should -Be 3
        $results[0].Dependent   | Should -Be "dbatoolsci_circrefA"
        $results[0].Tier        | Should -Be 0
        $results[1].Dependent   | Should -Be "dbatoolsci_circrefB"
        $results[1].Tier        | Should -Be 1
        $results[2].Dependent   | Should -Be "dbatoolsci_circrefA"
        $results[2].Tier        | Should -Be 2
    }
}

