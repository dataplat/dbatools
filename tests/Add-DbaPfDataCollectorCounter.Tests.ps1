param($ModuleName = 'dbatools')

Describe "Add-DbaPfDataCollectorCounter" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaPfDataCollectorCounter
        }
        $paramList = @(
            'ComputerName',
            'Credential',
            'CollectorSet',
            'Collector',
            'Counter',
            'InputObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | 
                Import-DbaPfDataCollectorSetTemplate |
                Get-DbaPfDataCollector | 
                Get-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' | 
                Remove-DbaPfDataCollectorCounter -Confirm:$false
        }

        AfterAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | 
                Remove-DbaPfDataCollectorSet -Confirm:$false
        }

        It "returns the correct values" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | 
                Get-DbaPfDataCollector | 
                Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'
            
            $results.DataCollectorSet | Should -Be 'Long Running Queries'
            $results.Name | Should -Be '\LogicalDisk(*)\Avg. Disk Queue Length'
        }
    }
}
