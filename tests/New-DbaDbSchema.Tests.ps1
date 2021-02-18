$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'SchemaName', 'SchemaOwner', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $instance1 = Connect-DbaInstance -SqlInstance $script:instance1
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Get-DbaProcess -SqlInstance $instance1, $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $instance1, $instance2 -Name $newDbName

        $userName = "user_$random"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $logins = New-DbaLogin -SqlInstance $instance1, $instance2 -Login $userName -Password $securePassword -Force

        $null = New-DbaDbUser -SqlInstance $instance1, $instance2 -Database $newDbName -Login $userName
    }

    AfterAll {
        $null = $newDbs | Remove-DbaDatabase -Confirm:$false
        $null = $logins | Remove-DbaLogin -Confirm:$false
    }

    Context "commands work as expected" {

        It "validates required SchemaName" {
            $schema = New-DbaDbSchema -SqlInstance $instance1
            $schema | Should -BeNullOrEmpty
        }

        It "validates required Database param" {
            $schema = New-DbaDbSchema -SqlInstance $instance1 -SchemaName TestSchema1
            $schema | Should -BeNullOrEmpty
        }

        It "creates a new schema" {
            $schema = New-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -SchemaName TestSchema1 -SchemaOwner $userName
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be $userName
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            $schemas = New-DbaDbSchema -SqlInstance $instance1, $instance2 -Database $newDbName -SchemaName TestSchema2, TestSchema3 -SchemaOwner $userName
            $schemas.Count | Should -Be 4
            $schemas.Owner | Should -Be $userName, $userName, $userName, $userName
            $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName
        }

        It "reports a warning that the schema already exists" {
            $schema = New-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -SchemaName TestSchema1 -SchemaOwner $userName
            $schema | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $schema = Get-DbaDatabase -SqlInstance $instance1 -Database $newDbName | New-DbaDbSchema -SchemaName TestSchema4
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be dbo
            $schema.Name | Should -Be TestSchema4
            $schema.Parent.Name | Should -Be $newDbName
        }
    }
}