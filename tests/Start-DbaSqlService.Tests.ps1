$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {

        $server = Connect-SqlInstance -SqlInstance $script:instance2
        $instanceName = $server.ServiceName
        $computerName = $server.NetName


        #Stop services using native cmdlets
        if ($instanceName -eq 'MSSQLSERVER') {
            $serviceName = "SQLSERVERAGENT"
        }
        else {
            $serviceName = "SqlAgent`$$instanceName"
        }
        Get-Service -ComputerName $computerName -Name $serviceName | Stop-Service -WarningAction SilentlyContinue | Out-Null

        It "starts the services back" {
            $services = Start-DbaSqlService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Running'
                $service.Status | Should Be 'Successful'
            }
        }

        #Stop services using native cmdlets
        if ($instanceName -eq 'MSSQLSERVER') {
            $serviceName = "SQLSERVERAGENT", "MSSQLSERVER"
        }
        else {
            $serviceName = "SqlAgent`$$instanceName", "MsSql`$$instanceName"
        }
        foreach ($sn in $servicename) { Get-Service -ComputerName $computerName -Name $sn | Stop-Service -WarningAction SilentlyContinue | Out-Null }

        It "starts the services back through pipeline" {
            $services = Get-DbaSqlService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent, Engine | Start-DbaSqlService
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Running'
                $service.Status | Should Be 'Successful'
            }
        }

        It "errors when passing an invalid InstanceName" {
            { Start-DbaSqlService -ComputerName $script:instance2 -Type 'Agent' -InstanceName 'ThisIsInvalid' -EnableException } | Should Throw 'No SQL Server services found with current parameters.'
        }
    }
}