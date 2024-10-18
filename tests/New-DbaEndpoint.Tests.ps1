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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String
        }
        It "Should have Protocol as a parameter" {
            $CommandUnderTest | Should -HaveParameter Protocol -Type System.String
        }
        It "Should have Role as a parameter" {
            $CommandUnderTest | Should -HaveParameter Role -Type System.String
        }
        It "Should have EndpointEncryption as a parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointEncryption -Type System.String
        }
        It "Should have EncryptionAlgorithm as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptionAlgorithm -Type System.String
        }
        It "Should have AuthenticationOrder as a parameter" {
            $CommandUnderTest | Should -HaveParameter AuthenticationOrder -Type System.String
        }
        It "Should have Certificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type System.String
        }
        It "Should have IPAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter IPAddress -Type System.Net.IPAddress
        }
        It "Should have Port as a parameter" {
            $CommandUnderTest | Should -HaveParameter Port -Type System.Int32
        }
        It "Should have SslPort as a parameter" {
            $CommandUnderTest | Should -HaveParameter SslPort -Type System.Int32
        }
        It "Should have Owner as a parameter" {
            $CommandUnderTest | Should -HaveParameter Owner -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
            $results = New-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring -Confirm:$false | Start-DbaEndpoint -Confirm:$false
            $results.EndpointType | Should -Be 'DatabaseMirroring'
        }

        It "creates it with the right owner" {
            $results = New-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring -Role Partner -Name Mirroring -Confirm:$false | Start-DbaEndpoint -Confirm:$false
            $sa = Get-SaLoginName -SqlInstance $global:instance2
            $results.Owner | Should -Be $sa
        }
    }
}
