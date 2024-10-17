param($ModuleName = 'dbatools')

Describe "Test-DbaSpn" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaSpn
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
    }

    Context "gets spn information" {
        BeforeAll {
            Mock -ModuleName $ModuleName -CommandName Resolve-DbaNetworkName -MockWith {
                [pscustomobject]@{
                    InputName        = $env:COMPUTERNAME
                    ComputerName     = $env:COMPUTERNAME
                    IPAddress        = "127.0.0.1"
                    DNSHostName      = $env:COMPUTERNAME
                    DNSDomain        = $env:COMPUTERNAME
                    Domain           = $env:COMPUTERNAME
                    DNSHostEntry     = $env:COMPUTERNAME
                    FQDN             = $env:COMPUTERNAME
                    FullComputerName = $env:COMPUTERNAME
                }
            }
            $results = Test-DbaSpn -ComputerName $env:COMPUTERNAME -WarningAction SilentlyContinue
        }

        It "returns some results" {
            $results.RequiredSPN | Should -Not -BeNullOrEmpty
        }

        It "has the right properties for each result" {
            foreach ($result in $results) {
                $result.RequiredSPN | Should -Match 'MSSQLSvc'
                $result.Cluster | Should -Be $false
                $result.TcpEnabled | Should -Be $true
                $result.IsSet | Should -BeOfType [bool]
            }
        }
    }
}
