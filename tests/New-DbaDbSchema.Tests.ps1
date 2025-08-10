$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Schema', 'SchemaOwner', 'InputObject', 'EnableException'
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
        $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName

        $userName = "user_$random"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $logins = New-DbaLogin -SqlInstance $server1, $server2 -Login $userName -Password $securePassword -Force

        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName
    }

    AfterAll {
        $null = $newDbs | Remove-DbaDatabase -Confirm:$false
        $null = $logins | Remove-DbaLogin -Confirm:$false
    }

    Context "commands work as expected" {

        It "validates required Schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -WarningAction SilentlyContinue -WarningVariable WarVar
            $WarVar | Should -Match "Schema is required"
            $schema | Should -BeNullOrEmpty
        }

        It "validates required Database param" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Schema TestSchema1 -WarningAction SilentlyContinue -WarningVariable WarVar
            $WarVar | Should -Match "Database is required when SqlInstance is specified"
            $schema | Should -BeNullOrEmpty
        }

        It "creates a new schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -SchemaOwner $userName
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be $userName
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            $schemas = New-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3 -SchemaOwner $userName
            $schemas.Count | Should -Be 4
            $schemas.Owner | Should -Be $userName, $userName, $userName, $userName
            $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName
        }

        It "reports a warning that the schema already exists" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -SchemaOwner $userName -WarningAction SilentlyContinue -WarningVariable WarVar
            $WarVar | Should -Match "Schema TestSchema1 already exists in the database"
            $schema | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $schema = Get-DbaDatabase -SqlInstance $server1 -Database $newDbName | New-DbaDbSchema -Schema TestSchema4
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be dbo
            $schema.Name | Should -Be TestSchema4
            $schema.Parent.Name | Should -Be $newDbName
        }
    }
}
