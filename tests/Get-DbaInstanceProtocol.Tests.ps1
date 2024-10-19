param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceProtocol" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceProtocol
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaInstanceProtocol -ComputerName $global:instance1, $global:instance2
        }

        It "shows some services" {
            $results.DisplayName | Should -Not -BeNullOrEmpty
        }

        It "can get TCPIP" {
            $tcpResults = $results | Where-Object Name -eq Tcp
            foreach ($result in $tcpResults) {
                $result.Name | Should -Be "Tcp"
            }
        }
    }
}
