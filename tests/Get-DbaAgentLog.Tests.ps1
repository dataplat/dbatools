$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LogNumber', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command gets agent log" {
        $results = Get-DbaAgentLog -SqlInstance $script:instance2
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Results contain SQLServerAgent version" {
            $results.text -like '`[100`] Microsoft SQLServerAgent version*' | Should Be $true
        }
        It "LogDate is a DateTime type" {
            $($results | Select-Object -first 1).LogDate | Should BeOfType DateTime
        }
    }
    Context "Command gets current agent log using LogNumber parameter" {
        $results = Get-DbaAgentLog -SqlInstance $script:instance2 -LogNumber 0
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
    }
}