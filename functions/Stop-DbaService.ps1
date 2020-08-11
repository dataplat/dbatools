function Stop-DbaService {
    <#
    .SYNOPSIS
        Stops SQL Server services on a computer.

    .DESCRIPTION
        Stops the SQL Server related services on one or more computers. Will follow SQL Server service dependencies.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

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
        A collection of services from Get-DbaService

    .PARAMETER Force
        Use this switch to stop dependent services before proceeding with the specified service

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
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS")]
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
            if ($Type) { $serviceParams.Type = $Type }
            if ($Credential) { $serviceParams.Credential = $Credential }
            if ($EnableException) { $serviceParams.Silent = $EnableException }
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
            if ($Force -and $service.ServiceType -eq 'Engine' -and !($processArray | Where-Object { $_.ServiceType -eq 'Agent' -and $_.InstanceName -eq $service.InstanceName -and $_.ComputerName -eq $service.ComputerName })) {
                #Construct parameters to call Get-DbaService
                $serviceParams = @{
                    ComputerName = $service.ComputerName
                    InstanceName = $service.InstanceName
                    Type         = 'Agent'
                }
                if ($Credential) { $serviceParams.Credential = $Credential }
                if ($EnableException) { $serviceParams.EnableException = $EnableException }
                $processArray += @(Get-DbaService @serviceParams)
            }
        }
        if ($PSCmdlet.ShouldProcess("$ProcessArray", "Stopping Service")) {
            if ($processArray) {
                Update-ServiceStatus -InputObject $processArray -Action 'stop' -Timeout $Timeout -EnableException $EnableException
            } else {
                Stop-Function -EnableException $EnableException -Message "No SQL Server services found with current parameters." -Category ObjectNotFound
            }
        }
    }
}