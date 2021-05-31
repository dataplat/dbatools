$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'OutputType', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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