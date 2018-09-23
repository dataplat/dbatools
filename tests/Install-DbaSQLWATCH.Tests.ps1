$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $commonParamCount = ([System.Management.Automation.PSCmdlet]::CommonParameters).Count + 2
        [object[]]$params = (Get-ChildItem function:\Install-DbaSQLWATCH).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Branch', 'Database', 'Force', 'LocalFile', 'EnableException', 'ConnectionString'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $commonParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing SQLWATCH installer" {
        BeforeAll {
            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $server -Database $database -Confirm:$false
            Get-DbaAgentJob -SqlInstance $server | Where-Object {$PSItem.Name -like "DBA-PERF-*" } | Remove-DbaAgentJob
        }

        $results = Install-DbaSQLWATCH -SqlInstance $server -Database $database -Branch master -Force

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should Be $true
        }
        It "Returns an object with the expected properties" {
            $result = $results[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Dacpac,PublishXml,Database,Result,DeployOptions,SqlCmdVariableValues'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Installed tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $instance -Database $Database | Where-Object {($PSItem.Name -like "sql_perf_mon_*") -or ($PSItem.Name -like "logger_*")}).Count
            $tableCount | Should -BeGreaterThan 0
        }
        It "Installed views" {
            $viewCount = (Get-DbaDbView -SqlInstance $instance -Database $Database | Where-Object {$PSItem.Name -like "vw_sql_perf_mon_*" }).Count
            $viewCount | Should -BeGreaterThan 0
        }
        It "Installed stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $instance -Database $Database | Where-Object {($PSItem.Name -like "sp_sql_perf_mon_*") -or ($PSItem.Name -like "usp_logger_*")}).Count
            $sprocCount | Should -BeGreaterThan 0
        }
        It "Installed SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $instance | Where-Object {($PSItem.Name -like "SQLWATCH-*") -or ($PSItem.Name -like "DBA-PERF-*")}).Count
            $agentCount | Should -BeGreaterThan 0
        }

    }
}