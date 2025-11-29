function Stop-DbaService {
    <#
    .SYNOPSIS
        Stops SQL Server-related Windows services with proper dependency handling.

    .DESCRIPTION
        Stops SQL Server services including Database Engine, SQL Agent, Reporting Services, Analysis Services, Integration Services, PolyBase, Launchpad, and other components across one or more computers. Automatically handles service dependencies to prevent dependency conflicts during shutdown operations.

        Particularly useful for planned maintenance windows, troubleshooting service issues, or preparing servers for patching and reboots. The Force parameter allows stopping dependent services automatically, which is essential when stopping Database Engine services that have SQL Agent dependencies.

        Supports targeting specific service types or instances, making it ideal for selective service management in multi-instance environments. Can be combined with Get-DbaService for advanced filtering and bulk operations across entire SQL Server environments.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        Specifies the target computer(s) containing SQL Server services to stop. Accepts multiple computer names for bulk service management.
        Use this when you need to stop SQL Server services across multiple servers during maintenance windows or troubleshooting scenarios.

    .PARAMETER InstanceName
        Targets services belonging to specific SQL Server named instances. Filters results to match only the specified instance names.
        Essential in multi-instance environments where you need to stop services for particular instances while leaving others running.

    .PARAMETER SqlInstance
        Use a combination of computername and instancename to get the SQL Server related services for specific instances on specific computers.

        Parameters ComputerName and InstanceName will be ignored if SqlInstance is used.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Filters which SQL Server service types to stop. Valid options: Agent, Browser, Engine, FullText, SSAS, SSIS, SSRS, PolyBase, Launchpad.
        Use this when you need to stop specific service types across instances, such as stopping all SQL Agent services for patching while keeping Database Engine services running.

    .PARAMETER Timeout
        Sets the maximum wait time in seconds for each service stop operation before timing out. Default is 60 seconds, specify 0 to wait indefinitely.
        Increase this value for services that take longer to shut down gracefully, particularly in environments with large databases or heavy workloads.

    .PARAMETER InputObject
        Accepts service objects directly from Get-DbaService, allowing for advanced filtering and pipeline operations.
        Use this approach when you need complex service filtering that goes beyond the built-in ComputerName, InstanceName, and Type parameters.

    .PARAMETER Force
        Automatically stops dependent services when stopping SQL Server Database Engine services. Prevents dependency conflicts that would otherwise block the stop operation.
        Required when stopping Engine services that have dependent SQL Agent services running, as SQL Agent must be stopped first to avoid service dependency errors.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Tags: Service, Stop
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires Local Admin rights on destination computer(s).

    .LINK
        https://dbatools.io/Stop-DbaService

    .EXAMPLE
        PS C:\> Stop-DbaService -ComputerName sqlserver2014a

        Stops the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3'| Get-DbaService | Stop-DbaService

        Gets the SQL Server related services on computers sql1, sql2 and sql3 and stops them.

    .EXAMPLE
        PS C:\> Stop-DbaService -ComputerName sql1,sql2 -Instance MSSQLSERVER

        Stops the SQL Server services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> Stop-DbaService -ComputerName $MyServers -Type SSRS

        Stops the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
        PS C:\> Stop-DbaService -ComputerName sql1 -Type Engine -Force

        Stops SQL Server database engine services on sql1 forcing dependent SQL Server Agent services to stop as well.

    #>
    [CmdletBinding(DefaultParameterSetName = "Server", SupportsShouldProcess, ConfirmImpact = "Medium")]
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
        if ($Force) { $ConfirmPreference = 'none' }
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
                # Add dependent services (Agent, PolyBase) if not already in the array
                $dependentTypes = @('Agent', 'PolyBase')
                foreach ($depType in $dependentTypes) {
                    if (!($processArray | Where-Object { $_.ServiceType -eq $depType -and $_.InstanceName -eq $service.InstanceName -and $_.ComputerName -eq $service.ComputerName })) {
                        #Construct parameters to call Get-DbaService
                        $serviceParams = @{
                            ComputerName = $service.ComputerName
                            InstanceName = $service.InstanceName
                            Type         = $depType
                        }
                        if ($Credential) { $serviceParams.Credential = $Credential }
                        if ($EnableException) { $serviceParams.EnableException = $EnableException }
                        $processArray += @(Get-DbaService @serviceParams)
                    }
                }
            }
        }
        if ($PSCmdlet.ShouldProcess("$ProcessArray", "Stopping Service")) {
            if ($processArray) {
                $splatServiceStatus = @{
                    InputObject     = $processArray
                    Action          = "stop"
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