$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IgnoreUptime', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $credential = New-Object System.Management.Automation.PSCredential('sa', ('<YourStrong@Passw0rd>' | ConvertTo-SecureString -asPlainText -Force))
            $server = Connect-DbaInstance -SqlInstance "localhost:1433" -SqlCredential $credential
            $random = Get-Random
            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "create table $tableName (col1 int IDENTITY (1,1) NOT NULL,
            col2 int NOT NULL,
            CONSTRAINT $indexName PRIMARY KEY CLUSTERED (col1))
            insert into $tableName values (1)"
            $null = $server.Query($sql, 'tempdb')
            $lastRestart = $server.Databases['tempdb'].CreateDate
            $endDate = Get-Date -Date $lastRestart
            $diffDays = (New-TimeSpan -Start $endDate -End (Get-Date)).Days

            Mock Connect-SQLInstance -MockWith {
                $server = [PSCustomObject]@{
                    Name      = 'SQLServerName';
                    Databases = [object]@(
                        @{
                            Name   = 'tempdb';
                            CreateDate = '2020-01-03 20:05:17.290'
                        }
                    )
                }} -ModuleName dbatools
        }
        AfterAll {
            $sql = "drop table $tableName;"
            $null = $server.Query($sql, 'tempdb')
        }

        it "Should stop if uptime is less than 6 days" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $server
            $results -eq $null | Should Be $true
        }

        It "Should find unused index: $indexName" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $script:instance1 -IgnoreUptime
            $results.IndexName -contains $indexName | Should Be $true
        }
        It "Should find unused index: $indexName for specific database" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $script:instance1 -IgnoreUptime -Database tempdb
            $results.IndexName -contains $indexName | Should Be $true
        }
        It "Should exclude specific database" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $script:instance1 -IgnoreUptime -ExcludeDatabase tempdb
            $results.DatabaseName -contains 'tempdb' | Should Be $false
        }
    }
}