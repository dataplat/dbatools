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
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Endpoint parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type System.Object[]
        }
        It "Should have ExcludeEndpoint parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeEndpoint -Type System.Object[]
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
