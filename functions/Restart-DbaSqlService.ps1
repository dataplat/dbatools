function Restart-DbaSqlService {
    <#
    .SYNOPSIS
    Restarts SQL Server services on a computer.

    .DESCRIPTION
    Restarts the SQL Server related services on one or more computers. Will follow SQL Server service dependencies.

    Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
    The SQL Server (or server in general) that you're connecting to. This command handles named instances.

    .PARAMETER InstanceName
    Only affects services that belong to the specific instances.

    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.

    .PARAMETER Type
    Use -Type to collect only services of the desired SqlServiceType.
    Can be one of the following: "Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS"

    .PARAMETER Timeout
    How long to wait for the start/stop request completion before moving on. Specify 0 to wait indefinitely.

    .PARAMETER InputObject
    A collection of services from Get-DbaSqlService

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
    Prompts you for confirmation before running the cmdlet.

    .PARAMETER Force
    Will stop dependent SQL Server agents when stopping Engine services.

    .NOTES
    Author: Kirill Kravtsov( @nvarscar )

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2017 Chrissy LeMaire
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Restart-DbaSqlService

    .EXAMPLE
    Restart-DbaSqlService -ComputerName sqlserver2014a

    Restarts the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
    'sql1','sql2','sql3'| Get-DbaSqlService | Restart-DbaSqlService

    Gets the SQL Server related services on computers sql1, sql2 and sql3 and restarts them.

    .EXAMPLE
    Restart-DbaSqlService -ComputerName sql1,sql2 -Instance MSSQLSERVER

    Restarts the SQL Server services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
    Restart-DbaSqlService -ComputerName $MyServers -Type SSRS

    Restarts the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

    .EXAMPLE
    Restart-DbaSqlService -ComputerName sql1 -Type Engine -Force

    Restarts SQL Server database engine services on sql1 forcing dependent SQL Server Agent services to restart as well.
#>
    [CmdletBinding(DefaultParameterSetName = "Server", SupportsShouldProcess = $true)]
    Param (
        [Parameter(ParameterSetName = "Server", Position = 1)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [Alias("Instance")]
        [string[]]$InstanceName,
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS")]
        [string[]]$Type,
        [parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "Service")]
        [Alias("ServiceCollection")]
        [object[]]$InputObject,
        [int]$Timeout = 30,
        [PSCredential]$Credential,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $processArray = @()
        if ($PsCmdlet.ParameterSetName -eq "Server") {
            $serviceParams = @{ ComputerName = $ComputerName }
            if ($InstanceName) { $serviceParams.InstanceName = $InstanceName }
            if ($Type) { $serviceParams.Type = $Type }
            if ($Credential) { $serviceParams.Credential = $Credential }
            if ($EnableException) { $serviceParams.Silent = $EnableException }
            $InputObject = Get-DbaSqlService @serviceParams
        }
    }
    process {
        #Get all the objects from the pipeline before proceeding
        $processArray += $InputObject
    }
    end {
        $processArray = [array]($processArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.ServiceType -in $Type) })
        foreach ($service in $processArray) {
            if ($Force -and $service.ServiceType -eq 'Engine' -and !($processArray | Where-Object { $_.ServiceType -eq 'Agent' -and $_.InstanceName -eq $service.InstanceName -and $_.ComputerName -eq $service.ComputerName })) {
                Write-Message -Level Verbose -Message "Adding Agent service to the list for service $($service.ServiceName) on $($service.ComputerName), since -Force has been specified"
                #Construct parameters to call Get-DbaSqlService
                $serviceParams = @{
                    ComputerName = $service.ComputerName
                    InstanceName = $service.InstanceName
                    Type         = 'Agent'
                }
                if ($Credential) { $serviceParams.Credential = $Credential }
                if ($EnableException) { $serviceParams.Silent = $EnableException }
                $processArray += @(Get-DbaSqlService @serviceParams)
            }
        }
        if ($processArray) {
            $services = Update-ServiceStatus -InputObject $processArray -Action 'stop' -Timeout $Timeout -EnableException $EnableException
            foreach ($service in ($services | Where-Object { $_.Status -eq 'Failed'})) {
                $service
            }
            $services = $services | Where-Object { $_.Status -eq 'Successful'}
            if ($services) {
                Update-ServiceStatus -InputObject $services -Action 'restart' -Timeout $Timeout -EnableException $EnableException
            }
        }
        else { Stop-Function -EnableException $EnableException -Message "No SQL Server services found with current parameters." }
    }
}
