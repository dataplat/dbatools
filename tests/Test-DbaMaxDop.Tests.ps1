$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Connects to multiple instances" {
        It 'Returns two rows relative to the instances' {
            $results = Test-DbaMaxDop -SqlInstance $script:instance1, $script:instance2
            ($results | Where-Object Database -eq "N/A").Count | Should Be 2
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_testMaxDop"
        $server.Query("CREATE DATABASE $db1")
        $needed = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1
        $setupright = $true
        if ($needed.Count -ne 1) {
            $setupright = $false
            it "has failed setup" {
                Set-TestInconclusive -message "Setup failed"
            }
        }
    }
    AfterAll {
        if (-not $appveyor) {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1
        }
    }

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