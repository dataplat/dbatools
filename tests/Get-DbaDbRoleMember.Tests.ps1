param($ModuleName = 'dbatools')

Describe "Get-DbaDbRoleMember Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbRoleMember
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "Role",
            "ExcludeRole",
            "ExcludeFixedRole",
            "IncludeSystemUser",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaDbRoleMember Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $global:instance2
        $allDatabases = $instance.Databases
    }

    Context "Functionality" {
        It 'Excludes system users by default' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance

            $result.IsSystemObject | Should -Not -Contain $true
        }

        It 'Includes system users' {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -IncludeSystemUser

            $result.SmoUser.IsSystemObject | Should -Contain $true
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
