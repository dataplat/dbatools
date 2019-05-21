$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Role', 'ExcludeRole', 'ExcludeFixedRole', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $script:instance2
        $allDatabases = $instance.Databases
    }

    Context "Functionality" {
        It 'Returns Results' {
            $result = Get-DbaDbRole -SqlInstance $instance

            $result.Count | Should BeGreaterThan $allDatabases.Count
        }

        It 'Includes Fixed Roles' {
            $result = Get-DbaDbRole -SqlInstance $instance

            $result.IsFixedRole | Select-Object -Unique | Should -Contain $true
        }

        It 'Returns all role membership for all databases' {
            $result = Get-DbaDbRole -SqlInstance $instance

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly $allDatabases.Count
        }

        It 'Accepts a list of databases' {
            $result = Get-DbaDbRole -SqlInstance $instance -Database 'msdb'

            $result.Database | Select-Object -Unique | Should -Be 'msdb'
        }

        It 'Excludes databases' {
            $result = Get-DbaDbRole -SqlInstance $instance -ExcludeDatabase 'msdb'

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly ($allDatabases.Count - 1)
            $uniqueDatabases | Should -Not -Contain 'msdb'
        }

        It 'Accepts a list of roles' {
            $result = Get-DbaDbRole -SqlInstance $instance -Role 'db_owner'

            $result.Name | Select-Object -Unique | Should -Be 'db_owner'
        }

        It 'Excludes roles' {
            $result = Get-DbaDbRole -SqlInstance $instance -ExcludeRole 'db_owner'

            $result.Name | Select-Object -Unique | Should -Not -Contain 'db_owner'
        }

        It 'Excludes fixed roles' {
            $result = Get-DbaDbRole -SqlInstance $instance -ExcludeFixedRole

            $results.IsFixedRole | Should Not Contain $true
            $result.Name | Select-Object -Unique | Should -Not -Contain 'db_owner'
        }
    }
}