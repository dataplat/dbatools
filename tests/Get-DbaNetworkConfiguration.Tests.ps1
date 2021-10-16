$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'OutputType', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $resultsFull = Get-DbaNetworkConfiguration -SqlInstance $script:instance2
        $resultsTcpIpProperties = Get-DbaNetworkConfiguration -SqlInstance $script:instance2 -OutputType TcpIpProperties

        It "Should Return a Result" {
            $resultsFull | Should -Not -Be $null
            $resultsTcpIpProperties | Should -Not -Be $null
        }

        It "has the correct properties" {
            $ExpectedPropsFull = 'ComputerName,InstanceName,SqlInstance,SharedMemoryEnabled,NamedPipesEnabled,TcpIpEnabled,TcpIpProperties,TcpIpAddresses'.Split(',')
            ($resultsFull.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedPropsFull | Sort-Object)
            $ExpectedPropsTcpIpProperties = 'ComputerName,InstanceName,SqlInstance,Enabled,KeepAlive,ListenAll'.Split(',')
            ($resultsTcpIpProperties.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedPropsTcpIpProperties | Sort-Object)
        }
    }
}