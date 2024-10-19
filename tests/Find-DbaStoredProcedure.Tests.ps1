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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Pattern"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
            $CommandUnderTest | Should -HaveParameter IncludeSystemObjects
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases
            $CommandUnderTest | Should -HaveParameter EnableException
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
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database 'Master' -Query $ServerProcedure
        }
        AfterAll {
            $DropProcedure = "DROP PROCEDURE dbo.cp_dbatoolsci_sysadmin;"
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database 'Master' -Query $DropProcedure
        }
        It "Should find a specific StoredProcedure named cp_dbatoolsci_sysadmin" {
            $results = Find-DbaStoredProcedure -SqlInstance $global:instance2 -Pattern dbatools* -IncludeSystemDatabases
            $results.Name | Should -Contain "cp_dbatoolsci_sysadmin"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database master).ID
        }
    }

    Context "Command finds Procedures in a User Database" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_storedproceduredb'
            $StoredProcedure = @"
CREATE PROCEDURE dbo.sp_dbatoolsci_custom
AS
    SET NOCOUNT ON;
    PRINT 'Dbatools Rocks';
"@
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database 'dbatoolsci_storedproceduredb' -Query $StoredProcedure
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database 'dbatoolsci_storedproceduredb' -Confirm:$false
        }
        It "Should find a specific StoredProcedure named sp_dbatoolsci_custom" {
            $results = Find-DbaStoredProcedure -SqlInstance $global:instance2 -Pattern dbatools* -Database 'dbatoolsci_storedproceduredb'
            $results.Name | Should -Contain "sp_dbatoolsci_custom"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database dbatoolsci_storedproceduredb).ID
        }
        It "Should find sp_dbatoolsci_custom in dbatoolsci_storedproceduredb" {
            $results = Find-DbaStoredProcedure -SqlInstance $global:instance2 -Pattern dbatools* -Database 'dbatoolsci_storedproceduredb'
            $results.Database | Should -Contain "dbatoolsci_storedproceduredb"
        }
        It "Should find no results when Excluding dbatoolsci_storedproceduredb" {
            $results = Find-DbaStoredProcedure -SqlInstance $global:instance2 -Pattern dbatools* -ExcludeDatabase 'dbatoolsci_storedproceduredb'
            $results | Should -BeNullOrEmpty
        }
    }
}
