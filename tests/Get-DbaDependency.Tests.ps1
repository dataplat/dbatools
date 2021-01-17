$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'InputObject', 'AllowSystemObjects', 'Parents', 'IncludeSelf', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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
                            ,	ParentID INTEGER FOREIGN KEY REFERENCES dbo.dbatoolsci1(ID)
                            );

                            CREATE TABLE dbo.dbatoolsci3
                            (
                                ID INTEGER
                            ,	ParentID INTEGER FOREIGN KEY REFERENCES dbo.dbatoolsci2(ID)
                            );"


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
}