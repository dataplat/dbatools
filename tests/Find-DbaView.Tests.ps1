param($ModuleName = 'dbatools')

Describe "Find-DbaView" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaView
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern
        }
        It "Should have IncludeSystemObjects as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObjects
        }
        It "Should have IncludeSystemDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command finds Views in a System Database" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $ServerView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database 'Master' -Query $ServerView
        }
        AfterAll {
            $DropView = "DROP VIEW dbo.v_dbatoolsci_sysadmin;"
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database 'Master' -Query $DropView
        }

        It "Should find a specific View named v_dbatoolsci_sysadmin" {
            $results = Find-DbaView -SqlInstance $global:instance2 -Pattern dbatools* -IncludeSystemDatabases
            $results.Name | Should -Be "v_dbatoolsci_sysadmin"
        }
        It "Should find v_dbatoolsci_sysadmin in Master" {
            $results = Find-DbaView -SqlInstance $global:instance2 -Pattern dbatools* -IncludeSystemDatabases
            $results.Database | Should -Be "Master"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database Master).ID
        }
    }

    Context "Command finds View in a User Database" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_viewdb'
            $DatabaseView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database 'dbatoolsci_viewdb' -Query $DatabaseView
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database 'dbatoolsci_viewdb' -Confirm:$false
        }

        It "Should find a specific view named v_dbatoolsci_sysadmin" {
            $results = Find-DbaView -SqlInstance $global:instance2 -Pattern dbatools* -Database 'dbatoolsci_viewdb'
            $results.Name | Should -Be "v_dbatoolsci_sysadmin"
        }
        It "Should find v_dbatoolsci_sysadmin in dbatoolsci_viewdb Database" {
            $results = Find-DbaView -SqlInstance $global:instance2 -Pattern dbatools* -Database 'dbatoolsci_viewdb'
            $results.Database | Should -Be "dbatoolsci_viewdb"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database dbatoolsci_viewdb).ID
        }
        It "Should find no results when Excluding dbatoolsci_viewdb" {
            $results = Find-DbaView -SqlInstance $global:instance2 -Pattern dbatools* -ExcludeDatabase 'dbatoolsci_viewdb'
            $results | Should -BeNullOrEmpty
        }
    }
}
