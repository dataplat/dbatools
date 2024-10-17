param($ModuleName = 'dbatools')

Describe "Remove-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaEndpoint
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String[]
        }
        It "Should have AllEndpoints as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllEndpoints -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Endpoint[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
