param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceProtocol" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceProtocol
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
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
