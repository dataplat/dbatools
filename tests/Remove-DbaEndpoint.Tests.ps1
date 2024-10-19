param($ModuleName = 'dbatools')

Describe "Remove-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaEndpoint
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint
        }
        It "Should have AllEndpoints as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllEndpoints
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $endpoint = Get-DbaEndpoint -SqlInstance $global:instance2 | Where-Object EndpointType -eq DatabaseMirroring
            $create = $endpoint | Export-DbaScript -Passthru
            $null = $endpoint | Remove-DbaEndpoint -Confirm:$false
            $results = New-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring -Confirm:$false | Start-DbaEndpoint -Confirm:$false
        }

        AfterAll {
            if ($create) {
                Invoke-DbaQuery -SqlInstance $global:instance2 -Query "$create"
            }
        }

        It "removes an endpoint" {
            $results = Get-DbaEndpoint -SqlInstance $global:instance2 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
            $results.Status | Should -Be 'Removed'
        }
    }
}
