param($ModuleName = 'dbatools')

Describe "Set-DbaTcpPort" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaTcpPort
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Port as a parameter" {
            $CommandUnderTest | Should -HaveParameter Port -Type Int32[]
        }
        It "Should have IpAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter IpAddress -Type IPAddress[]
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $oldPort = (Get-DbaTcpPort -SqlInstance $global:instance2).Port
            $newPort = $oldPort + 1000
            $instance = [DbaInstance]$global:instance2
        }

        It "Should change the port" {
            $result = Set-DbaTcpPort -SqlInstance $global:instance2 -Port $newPort -Confirm:$false
            $result.Changes | Should -Match 'Changed TcpPort'
            $result.RestartNeeded | Should -Be $true
            $result.Restarted | Should -Be $false

            $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Type Engine -Force

            $setPort = (Get-DbaTcpPort -SqlInstance $global:instance2).Port
            $setPort | Should -Be $newPort
        }

        It "Should change the port back to the old value" {
            $result = Set-DbaTcpPort -SqlInstance $global:instance2 -Port $oldPort -Confirm:$false
            $result.Changes | Should -Match 'Changed TcpPort'
            $result.RestartNeeded | Should -Be $true
            $result.Restarted | Should -Be $false

            $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Type Engine -Force

            $setPort = (Get-DbaTcpPort -SqlInstance $global:instance2).Port
            $setPort | Should -Be $oldPort
        }
    }
}
