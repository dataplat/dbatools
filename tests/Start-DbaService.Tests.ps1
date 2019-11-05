$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'InstanceName', 'Type', 'InputObject', 'Timeout', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {

        $server = Connect-SqlInstance -SqlInstance $script:instance2
        $instanceName = $server.ServiceName
        $computerName = $server.NetName


        #Stop services using native cmdlets
        if ($instanceName -eq 'MSSQLSERVER') {
            $serviceName = "SQLSERVERAGENT"
        } else {
            $serviceName = "SqlAgent`$$instanceName"
        }
        Get-Service -ComputerName $computerName -Name $serviceName | Stop-Service -WarningAction SilentlyContinue | Out-Null

        It "starts the services back" {
            $services = Start-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Running'
                $service.Status | Should Be 'Successful'
            }
        }

        #Stop services using native cmdlets
        if ($instanceName -eq 'MSSQLSERVER') {
            $serviceName = "SQLSERVERAGENT", "MSSQLSERVER"
        } else {
            $serviceName = "SqlAgent`$$instanceName", "MsSql`$$instanceName"
        }
        foreach ($sn in $servicename) { Get-Service -ComputerName $computerName -Name $sn | Stop-Service -WarningAction SilentlyContinue | Out-Null }

        It "starts the services back through pipeline" {
            $services = Get-DbaService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent, Engine | Start-DbaService
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Running'
                $service.Status | Should Be 'Successful'
            }
        }

        It "errors when passing an invalid InstanceName" {
            { Start-DbaService -ComputerName $script:instance2 -Type 'Agent' -InstanceName 'ThisIsInvalid' -EnableException } | Should Throw 'No services found in relevant namespaces'
        }
    }
}