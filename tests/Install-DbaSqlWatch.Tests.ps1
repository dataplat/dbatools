$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'LocalFile', 'Force', 'PreRelease', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing SqlWatch installer" {
        BeforeAll {
            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $database")
        }
        AfterAll {
            Uninstall-DbaSqlWatch -SqlInstance $TestConfig.instance2 -Database $database
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $database -Confirm:$false
        }

        $results = Install-DbaSqlWatch -SqlInstance $TestConfig.instance2 -Database $database

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should Be $true
        }
        It "Returns an object with the expected properties" {
            $result = $results[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Database,Status,DashboardPath'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Installed tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }).Count
            $tableCount | Should -BeGreaterThan 0
        }
        It "Installed views" {
            $viewCount = (Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database $Database | Where-Object { $PSItem.Name -like "vw_sqlwatch_*" }).Count
            $viewCount | Should -BeGreaterThan 0
        }
        It "Installed stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $TestConfig.instance2 -Database $Database | Where-Object { $PSItem.Name -like "usp_sqlwatch_*" }).Count
            $sprocCount | Should -BeGreaterThan 0
        }
        It "Installed SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 | Where-Object {($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*")}).Count
            $agentCount | Should -BeGreaterThan 0
        }

    }
}
