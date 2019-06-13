$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaUptime -SqlInstance $script:instance1
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlServer,SqlUptime,WindowsUptime,SqlStartTime,WindowsBootTime,SinceSqlStart,SinceWindowsBoot'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
    }
    Context "Command can handle multiple SqlInstances" {
        $results = Get-DbaUptime -SqlInstance $script:instance1, $script:instance2
        It "Command resultset could contain 2 results" {
            $results.count | Should Be 2
        }
        foreach ($result in $results) {
            It "Windows up time should be more than SQL Uptime" {
                $result.SqlUptime | Should BeLessThan $result.WindowsUpTime
            }
        }
    }
    Context "Properties should return expected types" {
        $results = Get-DbaUptime -SqlInstance $script:instance1
        foreach ($result in $results) {
            It "SqlStartTime should be a DbaDateTime" {
                $result.SqlStartTime  | Should BeOfType DbaDateTime
            }
            It "WindowsBootTime should be a DbaDateTime" {
                $result.WindowsBootTime  | Should BeOfType DbaDateTime
            }
        }
    }
}