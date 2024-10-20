$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Name', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = Get-DbaProcess -SqlInstance $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName
        $db.Query("EXEC sys.sp_addextendedproperty @name=N'dbatoolz', @value=N'woo'")
        #$tempdb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database tempdb
        #$tempdb.Query("EXEC sys.sp_addextendedproperty @name=N'temptoolz', @value=N'woo2'")
    }

    AfterAll {
        $null = $db | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "finds an extended property on an instance" {
            $ep = Get-DbaExtendedProperty -SqlInstance $server2
            $ep.Count | Should -BeGreaterThan 0
        }

        It "finds a sequence in a single database" {
            $ep = Get-DbaExtendedProperty -SqlInstance $server2 -Database $db.Name
            $ep.Parent.Name | Select-Object -Unique | Should -Be $db.Name
            $ep.Count | Should -Be 1
        }

        It "supports piping databases" {
            $ep = $db | Get-DbaExtendedProperty -Name dbatoolz
            $ep.Name | Should -Be "dbatoolz"
        }
    }
}
