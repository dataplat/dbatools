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
    Context "Command finds Views in a System Database" {
        BeforeAll {
            $ServerView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'Master' -Query $ServerView
        }
        AfterAll {
            $DropView = "DROP VIEW dbo.v_dbatoolsci_sysadmin;"
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'Master' -Query $DropView
        }

        $results = Find-DbaView -SqlInstance $script:instance2 -Pattern dbatools* -IncludeSystemDatabases
        It "Should find a specific View named v_dbatoolsci_sysadmin" {
            $results.Name | Should Be "v_dbatoolsci_sysadmin"
        }
        It "Should find v_dbatoolsci_sysadmin in Master" {
            $results.Database | Should Be "Master"
        }
    }
    Context "Command finds View in a User Database" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_viewdb'
            $DatabaseView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database 'dbatoolsci_viewdb' -Query $DatabaseView
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database 'dbatoolsci_viewdb' -Confirm:$false
        }

        $results = Find-DbaView -SqlInstance $script:instance2 -Pattern dbatools* -Database 'dbatoolsci_viewdb'
        It "Should find a specific view named v_dbatoolsci_sysadmin" {
            $results.Name | Should Be "v_dbatoolsci_sysadmin"
        }
        It "Should find v_dbatoolsci_sysadmin in dbatoolsci_viewdb Database" {
            $results.Database | Should Be "dbatoolsci_viewdb"
        }
        $results = Find-DbaView -SqlInstance $script:instance2 -Pattern dbatools* -ExcludeDatabase 'dbatoolsci_viewdb'
        It "Should find no results when Excluding dbatoolsci_viewdb" {
            $results | Should Be $null
        }
    }
}