param($ModuleName = 'dbatools')

Describe "Copy-DbaEndpoint" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaEndpoint
        }
        $paramList = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'Endpoint',
            'ExcludeEndpoint',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Copy-DbaEndpoint Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $global:instance2 = $script:instance2
        $global:instance3 = $script:instance3

        Get-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        New-DbaEndpoint -SqlInstance $global:instance2 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5022 -Owner sa
        Get-DbaEndpoint -SqlInstance $global:instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
    }

    AfterAll {
        Get-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        New-DbaEndpoint -SqlInstance $global:instance2 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5022 -Owner sa
        Get-DbaEndpoint -SqlInstance $global:instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        New-DbaEndpoint -SqlInstance $global:instance3 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5023 -Owner sa
    }

    It "copies an endpoint" {
        $results = Copy-DbaEndpoint -Source $global:instance2 -Destination $global:instance3 -Endpoint dbatoolsci_MirroringEndpoint
        $results.DestinationServer | Should -Be $global:instance3
        $results.Status | Should -Be 'Successful'
        $results.Name | Should -Be 'dbatoolsci_MirroringEndpoint'
    }
}
