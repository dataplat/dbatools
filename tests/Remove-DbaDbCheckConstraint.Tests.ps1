$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemTable', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $dbname2 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname2

        $chkc1 = "dbatoolssci_chkc1_$(Get-Random)"
        $chkc2 = "dbatoolssci_chkc2_$(Get-Random)"
        $null = $server.Query("CREATE TABLE dbo.checkconstraint1(col int CONSTRAINT $chkc1 CHECK(col > 0));" , $dbname1)
        $null = $server.Query("CREATE TABLE dbo.checkconstraint2(col int CONSTRAINT $chkc2 CHECK(col > 0));" , $dbname2)
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1, $dbname2 -Confirm:$false
    }

    Context "commands work as expected" {

        It "removes an check constraint" {
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbCheckConstraint -SqlInstance $server -Database $dbname1 -Confirm:$false
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname1 | Should -BeNullOrEmpty
        }

        It "supports piping check constraint" {
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname2 | Remove-DbaDbCheckConstraint -Confirm:$false
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname2 | Should -BeNullOrEmpty
        }
    }
}