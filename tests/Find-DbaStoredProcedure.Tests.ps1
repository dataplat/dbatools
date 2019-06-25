$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Pattern', 'IncludeSystemObjects', 'IncludeSystemDatabases', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
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
        $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -IncludeSystemDatabases
        It "Should find a specific StoredProcedure named cp_dbatoolsci_sysadmin" {
            $results.Name | Should Be "cp_dbatoolsci_sysadmin"
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
        $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -Database 'dbatoolsci_storedproceduredb'
        It "Should find a specific StoredProcedure named sp_dbatoolsci_custom" {
            $results.Name | Should Be "sp_dbatoolsci_custom"
        }
        It "Should find sp_dbatoolsci_custom in dbatoolsci_storedproceduredb" {
            $results.Database | Should Be "dbatoolsci_storedproceduredb"
        }
        $results = Find-DbaStoredProcedure -SqlInstance $script:instance2 -Pattern dbatools* -ExcludeDatabase 'dbatoolsci_storedproceduredb'
        It "Should find no results when Excluding dbatoolsci_storedproceduredb" {
            $results | Should Be $null
        }
    }
}