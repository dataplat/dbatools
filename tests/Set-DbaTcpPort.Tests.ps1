$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'Port', 'IpAddress', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $oldPort = (Get-DbaTcpPort -SqlInstance $script:instance2).Port
        $newPort = $oldPort + 1000

        It "Should change the port" {
            $result = Set-DbaTcpPort -SqlInstance $script:instance2 -Port $newPort -Confirm:$false
            $result.Changes | Should -Match 'Changed TcpPort'
            $result.RestartNeeded | Should -Be $true
            $result.Restarted | Should -Be $false

            $setPort = (Get-DbaTcpPort -SqlInstance $script:instance2).Port
            $setPort | Should -Be $newPort
            # Restart-DbaService -ComputerName $script:instance2.ComputerName -InstanceName $script:instance2.InstanceName -Type Engine -Force
        }

        It "Should change the port back to the old value" {
            $result = Set-DbaTcpPort -SqlInstance $script:instance2 -Port $oldPort -Confirm:$false
            $result.Changes | Should -Match 'Changed TcpPort'
            $result.RestartNeeded | Should -Be $true
            $result.Restarted | Should -Be $false

            $setPort = (Get-DbaTcpPort -SqlInstance $script:instance2).Port
            $setPort | Should -Be $newPort
            # Restart-DbaService -ComputerName $script:instance2.ComputerName -InstanceName $script:instance2.InstanceName -Type Engine -Force
        }
    }
}