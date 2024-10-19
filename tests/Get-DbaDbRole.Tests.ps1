param($ModuleName = 'dbatools')

Describe "Get-DbaDbRole" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbRole
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Role",
                "ExcludeRole",
                "ExcludeFixedRole",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Functionality" {
        BeforeAll {
            $instance = Connect-DbaInstance -SqlInstance $global:instance2
            $allDatabases = $instance.Databases
        }

        It 'Returns Results' {
            $result = Get-DbaDbRole -SqlInstance $instance
            $result.Count | Should -BeGreaterThan $allDatabases.Count
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
            $result.IsFixedRole | Should -Not -Contain $true
            $result.Name | Select-Object -Unique | Should -Not -Contain 'db_owner'
        }
    }
}
