$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Role', 'ExcludeRole', 'ExcludeFixedRole', 'IncludeSystemUser', 'InputObject', 'EnableException'
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
        It 'Excludes system users by default' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance

            $result.IsSystemObject | Select-Object -Unique | Should -Not -Contain $true
        }

        It 'Includes system users' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -IncludeSystemUser

            $result.IsSystemObject | Select-Object -Unique | Should -Contain $true
        }

        It 'Returns all role membership for all databases' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -IncludeSystemUser

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly $allDatabases.Count
        }

        It 'Accepts a list of databases' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -Database 'msdb' -IncludeSystemUser

            $result.Database | Select-Object -Unique | Should -Be 'msdb'
        }

        It 'Excludes databases' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -ExcludeDatabase 'msdb' -IncludeSystemUser

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly ($allDatabases.Count - 1)
            $uniqueDatabases | Should -Not -Contain 'msdb'
        }

        It 'Accepts a list of roles' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -Role 'db_owner' -IncludeSystemUser

            $result.Role | Select-Object -Unique | Should -Be 'db_owner'
        }

        It 'Excludes roles' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -ExcludeRole 'db_owner' -IncludeSystemUser

            $result.Role | Select-Object -Unique | Should -Not -Contain 'db_owner'
        }

        It 'Excludes fixed roles' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -ExcludeFixedRole -IncludeSystemUser

            $result.Role | Select-Object -Unique | Should -Not -Contain 'db_owner'
        }
    }
}