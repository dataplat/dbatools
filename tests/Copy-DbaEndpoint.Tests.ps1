param($ModuleName = 'dbatools')

Describe "Copy-DbaEndpoint" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaEndpoint
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Endpoint",
                "ExcludeEndpoint",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

Describe "Copy-DbaEndpoint Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
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
