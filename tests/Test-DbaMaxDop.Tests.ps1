$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaMaxDop).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','Detailed','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_testMaxDop"
        $server.Query("CREATE DATABASE dbatoolsci_testMaxDop")
        $needed = Get-DbaDatabase -SqlInstance $script:instance2 -Database dbatoolsci_testMaxDop
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
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database dbatoolsci_testMaxDop
        }
    }

    Context "Command works on SQL Server 2016 or higher instances" {
        $results = Test-DbaMaxDop -SqlInstance $script:instance2

        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,DatabaseMaxDop,CurrentInstanceMaxDop,RecommendedMaxDop,Notes'.Split(',')
            foreach ($result in $results) {
                ($result.PSStandardMembers.DefaultDIsplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }
        }

        It "Should have only one result for database name of dbatoolsci_testMaxDop" {
            @($results | Where-Object Database -eq dbatoolsci_testMaxDop).Count | Should Be 1
        }
    }
}