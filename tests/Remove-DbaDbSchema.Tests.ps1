$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Schema', 'InputObject', 'EnableException'
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
    }

    AfterAll {
        $null = $newDbs | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "drops the schema" {
            $schema = New-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -SchemaName TestSchema1
            $schema.Count | Should -Be 1
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            Remove-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -Schema TestSchema1 -Confirm:$false

            (Get-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -SchemaName TestSchema1) | Should -BeNullOrEmpty

            $schemas = New-DbaDbSchema -SqlInstance $instance1, $instance2 -Database $newDbName -SchemaName TestSchema2, TestSchema3
            $schemas.Count | Should -Be 4
            $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName

            Remove-DbaDbSchema -SqlInstance $instance1, $instance2 -Database $newDbName -Schema TestSchema2, TestSchema3 -Confirm:$false

            (Get-DbaDbSchema -SqlInstance $instance1, $instance2 -Database $newDbName -SchemaName TestSchema2, TestSchema3) | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $schema = New-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -SchemaName TestSchema1
            $schema.Count | Should -Be 1
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            Get-DbaDatabase -SqlInstance $instance1 -Database $newDbName | Remove-DbaDbSchema -Schema TestSchema1 -Confirm:$false

            (Get-DbaDbSchema -SqlInstance $instance1 -Database $newDbName -SchemaName TestSchema1) | Should -BeNullOrEmpty
        }
    }
}