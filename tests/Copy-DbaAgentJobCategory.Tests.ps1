$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'CategoryType', 'JobCategory', 'AgentCategory', 'OperatorCategory', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci test category'
    }
    AfterAll {
        $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci test category'
    }

    Context "Command copies jobs properly" {
        It "returns one success" {
            $results = Copy-DbaAgentJobCategory -Source $script:instance2 -Destination $script:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name -eq "dbatoolsci test category"
            $results.Status -eq "Successful"
        }

        It "does not overwrite" {
            $results = Copy-DbaAgentJobCategory -Source $script:instance2 -Destination $script:instance3 -JobCategory 'dbatoolsci test category'
            $results.Name -eq "dbatoolsci test category"
            $results.Status -eq "Skipped"
        }
    }
}