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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "Port",
                "IpAddress",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
