$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {

        $server = Connect-SqlInstance -SqlInstance $script:instance2
        $instanceName = $server.ServiceName
        $computerName = $server.NetName

        It "stops some services" {
            $services = Stop-DbaSqlService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Stopped'
                $service.Status | Should Be 'Successful'
            }
        }

        #Start services using native cmdlets
        if ($instanceName -eq 'MSSQLSERVER') {
            $serviceName = "SQLSERVERAGENT"
        }
        else {
            $serviceName = "SqlAgent`$$instanceName"
        }
        Get-Service -ComputerName $computerName -Name $serviceName | Start-Service -WarningAction SilentlyContinue | Out-Null

        It "stops specific services based on instance name through pipeline" {
            $services = Get-DbaSqlService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent, Engine | Stop-DbaSqlService
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Stopped'
                $service.Status | Should Be 'Successful'
            }
        }

        #Start services using native cmdlets
        if ($instanceName -eq 'MSSQLSERVER') {
            $serviceName = "MSSQLSERVER", "SQLSERVERAGENT"
        }
        else {
            $serviceName = "MsSql`$$instanceName", "SqlAgent`$$instanceName"
        }
        foreach ($sn in $servicename) { Get-Service -ComputerName $computerName -Name $sn | Start-Service -WarningAction SilentlyContinue | Out-Null }

    }
}