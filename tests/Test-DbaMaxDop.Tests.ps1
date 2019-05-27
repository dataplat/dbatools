$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $db1 = "dbatoolsci_testMaxDop"
        $server.Query("CREATE DATABASE dbatoolsci_testMaxDop")
        $needed = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1
        $setupright = $true
        if (-not $needed) {
            $setupright = $false
        }
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1 | Remove-DbaDatabase -Confirm:$false
    }

    # Just not messin with this in appveyor
    if ($setupright) {
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
}