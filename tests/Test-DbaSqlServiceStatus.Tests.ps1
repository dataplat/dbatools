$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Connects to multiple instances" {
        It 'Returns two rows relative to the instances' {
            $results = Test-DbaSqlServiceStatus -SqlInstance $script:instance1, $script:instance2
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works on SQL Server 2016 or higher instances" {
        $results = Test-DbaMaxDop -SqlInstance $script:instance2

        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,DatabaseMaxDop,CurrentInstanceMaxDop,RecommendedMaxDop,Notes'.Split(',')
            foreach ($result in $results) {
                ($result.PSStandardMembers.DefaultDIsplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }
        }

        It "Should have only one result for database name of $db1" {
            @($results | Where-Object Database -eq $db1).Count | Should Be 1
        }
    }
}