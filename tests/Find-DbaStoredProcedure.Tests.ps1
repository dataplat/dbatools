param($ModuleName = 'dbatools')

Describe "Find-DbaStoredProcedure Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaStoredProcedure
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String
        }
        It "Should have IncludeSystemObjects as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObjects -Type Switch
        }
        It "Should have IncludeSystemDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Find-DbaStoredProcedure Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command finds Procedures in a System Database" {
        BeforeAll {
            $ServerProcedure = @"
CREATE PROCEDURE dbo.cp_dbatoolsci_sysadmin
AS
    SET NOCOUNT ON;
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'Master' -Query $ServerProcedure
        }
        AfterAll {
            $DropProcedure = "DROP PROCEDURE dbo.cp_dbatoolsci_sysadmin;"
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'Master' -Query $DropProcedure
        }
        It "Should find a specific StoredProcedure named cp_dbatoolsci_sysadmin" {
            $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -IncludeSystemDatabases
            $results.Name | Should -Contain "cp_dbatoolsci_sysadmin"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $script:instance2 -Database master).ID
        }
    }

    Context "Command finds Procedures in a User Database" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_storedproceduredb'
            $StoredProcedure = @"
CREATE PROCEDURE dbo.sp_dbatoolsci_custom
AS
    SET NOCOUNT ON;
    PRINT 'Dbatools Rocks';
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'dbatoolsci_storedproceduredb' -Query $StoredProcedure
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database 'dbatoolsci_storedproceduredb' -Confirm:$false
        }
        It "Should find a specific StoredProcedure named sp_dbatoolsci_custom" {
            $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -Database 'dbatoolsci_storedproceduredb'
            $results.Name | Should -Contain "sp_dbatoolsci_custom"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $script:instance2 -Database dbatoolsci_storedproceduredb).ID
        }
        It "Should find sp_dbatoolsci_custom in dbatoolsci_storedproceduredb" {
            $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -Database 'dbatoolsci_storedproceduredb'
            $results.Database | Should -Contain "dbatoolsci_storedproceduredb"
        }
        It "Should find no results when Excluding dbatoolsci_storedproceduredb" {
            $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -ExcludeDatabase 'dbatoolsci_storedproceduredb'
            $results | Should -BeNullOrEmpty
        }
    }
}
