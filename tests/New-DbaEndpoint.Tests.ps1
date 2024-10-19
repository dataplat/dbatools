param($ModuleName = 'dbatools')

Describe "New-DbaEndpoint" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaEndpoint
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "Type",
                "Protocol",
                "Role",
                "EndpointEncryption",
                "EncryptionAlgorithm",
                "AuthenticationOrder",
                "Certificate",
                "IPAddress",
                "Port",
                "SslPort",
                "Owner",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $endpoint = Get-DbaEndpoint -SqlInstance $global:instance2 | Where-Object EndpointType -eq DatabaseMirroring
            $create = $endpoint | Export-DbaScript -Passthru
            Get-DbaEndpoint -SqlInstance $global:instance2 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        }
        AfterAll {
            Get-DbaEndpoint -SqlInstance $global:instance2 | Where-Object EndpointType -eq DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
            if ($create) {
                Invoke-DbaQuery -SqlInstance $global:instance2 -Query "$create"
            }
        }

        It "creates an endpoint of the db mirroring type" {
            $results = New-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring | Start-DbaEndpoint
            $results.EndpointType | Should -Be 'DatabaseMirroring'
        }

        It "creates it with the right owner" {
            $results = New-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring | Start-DbaEndpoint
            $sa = Get-SaLoginName -SqlInstance $global:instance2
            $results.Owner | Should -Be $sa
        }
    }
}
