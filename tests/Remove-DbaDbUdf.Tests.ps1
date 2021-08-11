$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemUdf', 'Schema', 'ExcludeSchema', 'Name', 'ExcludeName', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1

        $udf1 = "dbatoolssci_udf1_$(Get-Random)"
        $udf2 = "dbatoolssci_udf2_$(Get-Random)"
        $null = $server.Query("CREATE FUNCTION dbo.$udf1 (@a int) RETURNS TABLE AS RETURN (SELECT 1 a);" , $dbname1)
        $null = $server.Query("CREATE FUNCTION dbo.$udf2 (@a int) RETURNS TABLE AS RETURN (SELECT 1 a);" , $dbname1)
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1 -Confirm:$false
    }

    Context "commands work as expected" {

        It "removes an user defined function" {
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 -Confirm:$false
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1  | Should -BeNullOrEmpty
        }

        It "supports piping user defined function" {
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Should -Not -BeNullOrEmpty
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Remove-DbaDbUdf -Confirm:$false
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Should -BeNullOrEmpty
        }
    }
}