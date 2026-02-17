function Restart-DbaService {
    <#
    .SYNOPSIS
        Restarts SQL Server services with proper dependency handling and service ordering.

    .DESCRIPTION
        Restarts SQL Server services across multiple computers while automatically managing service dependencies and restart order. This function performs a controlled stop-then-restart sequence, ensuring that dependent services like SQL Agent are properly handled when restarting the Database Engine. You can target specific service types (Engine, Agent, SSRS, SSAS, etc.) or restart all SQL Server services on a system, making it ideal for maintenance windows or applying configuration changes that require service restarts.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        Specifies the computer names where SQL Server services will be restarted. Accepts multiple computer names for batch operations.
        Use this when you need to restart services across multiple SQL Server hosts during maintenance windows or after configuration changes.

    .PARAMETER InstanceName
        Restricts the restart operation to services belonging to specific SQL Server instances (like MSSQLSERVER, SQLEXPRESS, or named instances).
        Use this when you have multiple instances on a server but only need to restart services for specific instances, avoiding unnecessary downtime for other instances.

    .PARAMETER SqlInstance
        Use a combination of computername and instancename to get the SQL Server related services for specific instances on specific computers.

        Parameters ComputerName and InstanceName will be ignored if SqlInstance is used.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Specifies which SQL Server service types to restart: Agent, Browser, Engine, FullText, SSAS, SSIS, SSRS, PolyBase, or Launchpad.
        Use this when you need to restart only specific services rather than all SQL Server services, such as restarting just SQL Agent after job configuration changes or only SSRS after report deployment.

    .PARAMETER Timeout
        Sets the maximum time in seconds to wait for each service stop/start operation to complete before timing out. Defaults to 60 seconds.
        Increase this value for busy systems or when restarting services with large databases that may take longer to shut down gracefully. Set to 0 for infinite wait.

    .PARAMETER InputObject
        Accepts service objects from Get-DbaService to restart specific services that have already been filtered or identified.
        Use this when you need to restart a predefined set of services, typically by piping results from Get-DbaService with custom filtering or from previously saved service collections.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER Force
        Automatically includes dependent services (SQL Agent, PolyBase, Launchpad) when restarting Database Engine services to ensure proper shutdown sequence.
        Use this when restarting Engine services to avoid dependency conflicts and ensure all related services restart cleanly, particularly important during major configuration changes or patches.

    .NOTES
        Tags: Service, Instance, Restart
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .LINK
        https://dbatools.io/Restart-DbaService

    .OUTPUTS
        dbatools.DbaSqlService

        Returns one object per service that was processed with the following properties:
        - ComputerName: The name of the computer where the service is running
        - InstanceName: The SQL Server instance name the service belongs to
        - ServiceName: The Windows service name (MSSQLSERVER, MSSQL$NAMED, SQLSERVERAGENT, etc.)
        - ServiceType: The type of service (Engine, Agent, Browser, FullText, SSAS, SSIS, SSRS, PolyBase, Launchpad)
        - Status: The result of the restart operation (Successful, Failed, or other status values)

        Services that failed to stop are returned before services that successfully restarted. This allows you to identify which services encountered issues during the restart process.

        If -Force is specified with Engine services, dependent services (Agent, PolyBase, Launchpad) are automatically included and restarted as part of the operation.

    .EXAMPLE
        PS C:\> Restart-DbaService -ComputerName sqlserver2014a

        Restarts the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3'| Get-DbaService | Restart-DbaService

        Gets the SQL Server related services on computers sql1, sql2 and sql3 and restarts them.

    .EXAMPLE
        PS C:\> Restart-DbaService -ComputerName sql1,sql2 -InstanceName MSSQLSERVER

        Restarts the SQL Server services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> Restart-DbaService -ComputerName $MyServers -Type SSRS

        Restarts the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
        PS C:\> Restart-DbaService -ComputerName sql1 -Type Engine -Force

        Restarts SQL Server database engine services on sql1 forcing dependent SQL Server Agent services to restart as well.

    #>
    [CmdletBinding(DefaultParameterSetName = "Server", SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = "Server", Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Alias("Instance")]
        [string[]]$InstanceName,
        [Parameter(ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad")]
        [string[]]$Type,
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "Service")]
        [Alias("ServiceCollection")]
        [object[]]$InputObject,
        [int]$Timeout = 60,
        [PSCredential]$Credential,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $processArray = @()
        if ($PsCmdlet.ParameterSetName -eq "Server") {
            $serviceParams = @{ ComputerName = $ComputerName }
            if ($InstanceName) { $serviceParams.InstanceName = $InstanceName }
            if ($SqlInstance) { $serviceParams.SqlInstance = $SqlInstance }
            if ($Type) { $serviceParams.Type = $Type }
            if ($Credential) { $serviceParams.Credential = $Credential }
            if ($EnableException) { $serviceParams.EnableException = $EnableException }
            $InputObject = Get-DbaService @serviceParams
        }
    }
    process {
        #Get all the objects from the pipeline before proceeding
        $processArray += $InputObject
    }
    end {
        $processArray = [array]($processArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.ServiceType -in $Type) })
        foreach ($service in $processArray) {
            if ($Force -and $service.ServiceType -eq 'Engine') {
                $dependentServices = @()
                foreach ($dependentService in @("Agent", "PolyBase", "Launchpad")) {
                    if (!($processArray | Where-Object { $_.ServiceType -eq $dependentService -and $_.InstanceName -eq $service.InstanceName -and $_.ComputerName -eq $service.ComputerName })) {
                        Write-Message -Level Verbose -Message "Adding $dependentService service to the list for service $($service.ServiceName) on $($service.ComputerName), since -Force has been specified"
                        $dependentServices += $dependentService
                    }
                }
                if ($dependentServices.Count -gt 0) {
                    #Construct parameters to call Get-DbaService
                    $serviceParams = @{
                        ComputerName  = $service.ComputerName
                        InstanceName  = $service.InstanceName
                        Type          = $dependentServices
                        WarningAction = 'SilentlyContinue'

                    }
                    if ($Credential) { $serviceParams.Credential = $Credential }
                    if ($EnableException) { $serviceParams.EnableException = $EnableException }
                    $processArray += @(Get-DbaService @serviceParams)
                }
            }
        }
        if ($processArray) {
            if ($PSCmdlet.ShouldProcess("$ProcessArray", "Restarting Service")) {
                $splatServiceStatus = @{
                    InputObject     = $processArray
                    Action          = "stop"
                    Timeout         = $Timeout
                    EnableException = $EnableException
                }
                if ($Credential) { $splatServiceStatus.Credential = $Credential }
                $services = Update-ServiceStatus @splatServiceStatus
                foreach ($service in ($services | Where-Object { $_.Status -eq 'Failed' })) {
                    $service
                }
                $services = $services | Where-Object { $_.Status -eq 'Successful' }
                if ($services) {
                    $splatServiceStatus.InputObject = $services
                    $splatServiceStatus.Action = "restart"
                    Update-ServiceStatus @splatServiceStatus
                }
            }
        } else {
            Stop-Function -EnableException $EnableException -Message "No SQL Server services found with current parameters."
        }
    }
}