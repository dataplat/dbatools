$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Schema', 'SchemaOwner', 'IncludeSystemDatabases', 'IncludeSystemSchemas', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName

        $schemaName = "TestSchema"
        $schemaName2 = "TestSchema2"

        $userName = "user_$random"
        $userName2 = "user2_$random"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $logins = New-DbaLogin -SqlInstance $server1, $server2 -Login $userName, $userName2 -Password $securePassword -Force

        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName
        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName2

        $newDbs[0].Query("CREATE SCHEMA $schemaName AUTHORIZATION [$userName]")
        $newDbs[0].Schemas.Refresh()
        $newDbs[1].Query("CREATE SCHEMA $schemaName2 AUTHORIZATION [$userName2]")
        $newDbs[1].Schemas.Refresh()
    }

    AfterAll {
        $null = $newDbs | Remove-DbaDatabase -Confirm:$false
        $null = $logins | Remove-DbaLogin -Confirm:$false
    }

    Context "commands work as expected" {

        It "get all schemas from all databases including system dbs and schemas" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -IncludeSystemDatabases -IncludeSystemSchemas
            $schemas.Count | Should -BeGreaterThan 1
            $schemas.Parent.Name | Should -Contain master
            $schemas.Parent.Name | Should -Contain msdb
            $schemas.Parent.Name | Should -Contain model
            $schemas.Parent.Name | Should -Contain tempdb
            $schemas.Name | Should -Contain dbo
            $schemas.Name | Should -Contain $schemaName
        }

        It "get all schemas from user databases including system schemas" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -IncludeSystemSchemas
            $schemas.Count | Should -BeGreaterThan 1
            $schemas.Parent.Name | Should -Not -Contain master
            $schemas.Parent.Name | Should -Not -Contain msdb
            $schemas.Parent.Name | Should -Not -Contain model
            $schemas.Parent.Name | Should -Not -Contain tempdb
            $schemas.Name | Should -Contain dbo
            $schemas.Name | Should -Contain $schemaName
        }

        It "get non-system schemas from a user database" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Schema $schemaName
            $schemas.Name | Should -Contain $schemaName
            $schemas.Parent.Name | Should -Contain $newDbName
        }

        It "get a schema by name from a user database" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema $schemaName
            $schemas.Count | Should -Be 1
            $schemas.Name | Should -Be $schemaName
            $schemas.DatabaseName | Should -Be $newDbName
            $schemas.DatabaseId | Should -Be $newDbs[0].Id
            $schemas.ComputerName | Should -Be $server1.ComputerName
        }

        It "get the dbo schema" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema dbo -IncludeSystemSchemas
            $schemas.Count | Should -Be 1
            $schemas.Name | Should -Be dbo
        }

        It "get schemas by owner from a user database" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -SchemaOwner $userName
            $schemas.Count | Should -Be 1
            $schemas.Name | Should -Be $schemaName
            $schemas.Owner | Should -Be $userName
            $schemas.Parent.Name | Should -Be $newDbName

            $schemas = Get-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -SchemaOwner $userName, $userName2
            $schemas.Count | Should -Be 2
            $schemas.Name | Should -Be $schemaName, $schemaName2
            $schemas.Owner | Should -Be $userName, $userName2
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName
        }

        It "supports piping databases" {
            $schemas = $newDbs | Get-DbaDbSchema -Schema $schemaName, $schemaName2
            $schemas.Count | Should -Be 2
            $schemas.Owner | Should -Be $userName, $userName2
            $schemas.Name | Should -Be $schemaName, $schemaName2
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName
        }

        It "get a schema and then change the owner" {
            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema $schemaName
            $schemas.Count | Should -Be 1
            $schemas.Owner | Should -Be $userName

            $schemas.Owner = $userName2
            $schemas.Alter()

            $schemas = Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema $schemaName
            $schemas.Count | Should -Be 1
            $schemas.Owner | Should -Be $userName2
        }

        It "get a schema and then drop it (assuming that it does not contain any objects)" {
            $schemas = Get-DbaDbSchema -SqlInstance $server2 -Database $newDbName -Schema $schemaName2
            $schemas.Count | Should -Be 1
            $schemas.Owner | Should -Be $userName2

            $schemas.Drop()

            $schemas = Get-DbaDbSchema -SqlInstance $server2 -Database $newDbName -Schema $schemaName2
            $schemas | Should -BeNullOrEmpty
        }
    }
}
