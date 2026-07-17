function Start-DbaService {
    <#
    .SYNOPSIS
        Starts SQL Server related services across multiple computers while respecting service dependencies.

    .DESCRIPTION
        Starts SQL Server services (Engine, Agent, Browser, FullText, SSAS, SSIS, SSRS, PolyBase, Launchpad) on one or more computers following proper dependency order. This function handles the complexity of starting services in the correct sequence so you don't have to manually determine which services depend on others. Commonly used after maintenance windows, server reboots, or when troubleshooting stopped services across an environment.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        Specifies the computer names where SQL Server services should be started. Accepts multiple computer names for bulk operations.
        Use this when you need to start services across multiple servers simultaneously, such as after a maintenance window or environment-wide restart.

    .PARAMETER InstanceName
        Filters services to only those belonging to specific named instances. Does not affect default instance (MSSQLSERVER) services.
        Use this when you have multiple instances on the same server and only want to start services for specific named instances like SQL2019 or REPORTING.

    .PARAMETER SqlInstance
        Use a combination of computername and instancename to get the SQL Server related services for specific instances on specific computers.

        Parameters ComputerName and InstanceName will be ignored if SqlInstance is used.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Filters to specific SQL Server service types rather than starting all services. Valid types: Agent, Browser, Engine, FullText, SSAS, SSIS, SSRS, PolyBase, Launchpad.
        Use this when you need to start only specific service types, such as starting just SQL Agent after maintenance or only SSRS services on reporting servers.

    .PARAMETER Timeout
        Sets the maximum time in seconds to wait for each service to start before moving to the next service. Defaults to 60 seconds.
        Increase this value for slow-starting services or when starting services on heavily loaded servers. Set to 0 to wait indefinitely.

    .PARAMETER InputObject
        Accepts service objects from Get-DbaService through the pipeline for targeted service operations.
        Use this when you need fine-grained control over which specific services to start, such as when Get-DbaService has filtered to stopped services only.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Tags: Service, SqlServer, Instance, Connect
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .OUTPUTS
        System.ServiceProcess.ServiceController

        Returns one ServiceController object per service that was successfully started. Each object represents a SQL Server related service on the target computer(s).

        Default display properties (from ServiceController):
        - Name: The service name (e.g., MSSQLSERVER, SQLSERVERAGENT, MSSQLServerOlapService)
        - DisplayName: The friendly display name of the service
        - Status: The current status of the service (Running, Stopped, StartPending, StopPending, etc.)
        - StartType: How the service starts (Boot, System, Automatic, Manual, Disabled)

        Additional properties available from ServiceController:
        - ServiceName: The name of the service
        - ServiceType: The type of service
        - CanPauseAndContinue: Boolean indicating if the service can be paused and resumed
        - CanShutdown: Boolean indicating if the service should be notified of system shutdown
        - CanStop: Boolean indicating if the service can be stopped
        - ServiceHandle: The service's Windows handle
        - DependentServices: Collection of services that depend on this service
        - ServicesDependedOn: Collection of services that this service depends on
        - RequiredServices: Collection of services required for this service to run

        Returns nothing if no services are found matching the specified parameters, or if the -WhatIf parameter is used.

    .LINK
        https://dbatools.io/Start-DbaService

    .EXAMPLE
        PS C:\> Start-DbaService -ComputerName sqlserver2014a

        Starts the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3'| Get-DbaService | Start-DbaService

        Gets the SQL Server related services on computers sql1, sql2 and sql3 and starts them.

    .EXAMPLE
        PS C:\> Start-DbaService -ComputerName sql1,sql2 -Instance MSSQLSERVER

        Starts the SQL Server services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> Start-DbaService -ComputerName $MyServers -Type SSRS

        Starts the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

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
        $processArray = $processArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.ServiceType -in $Type) }
        if ($PSCmdlet.ShouldProcess("$ProcessArray", "Starting Service")) {
            if ($processArray) {
                $splatServiceStatus = @{
                    InputObject     = $processArray
                    Action          = "start"
                    Timeout         = $Timeout
                    EnableException = $EnableException
                }
                if ($Credential) { $splatServiceStatus.Credential = $Credential }
                Update-ServiceStatus @splatServiceStatus
            } else {
                Stop-Function -EnableException $EnableException -Message "No SQL Server services found with current parameters." -Category ObjectNotFound
            }
        }
    }
}