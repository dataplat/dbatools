function Start-DbaSqlService {
    <#
    .SYNOPSIS
    Starts SQL Server services on a computer.

    .DESCRIPTION
    Starts the SQL Server related services on one or more computers. Will follow SQL Server service dependencies.

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

    .PARAMETER ServiceCollection
    A collection of services from Get-DbaSqlService

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
    Prompts you for confirmation before running the cmdlet.

    .NOTES
    Author: Kirill Kravtsov( @nvarscar )
    Tags:
    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2017 Chrissy LeMaire
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Start-DbaSqlService

    .EXAMPLE
    Start-DbaSqlService -ComputerName sqlserver2014a

    Starts the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE
    'sql1','sql2','sql3'| Get-DbaSqlService | Start-DbaSqlService

    Gets the SQL Server related services on computers sql1, sql2 and sql3 and starts them.

    .EXAMPLE
    Start-DbaSqlService -ComputerName sql1,sql2 -Instance MSSQLSERVER

    Starts the SQL Server services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
    Start-DbaSqlService -ComputerName $MyServers -Type SSRS

    Starts the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

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
        [object[]]$ServiceCollection,
        [int]$Timeout = 30,
        [PSCredential]$Credential,
        [switch][Alias('Silent')]$EnableException
    )
    begin {
        $processArray = @()
        if ($PsCmdlet.ParameterSetName -eq "Server") {
            $serviceParams = @{ ComputerName = $ComputerName }
            if ($InstanceName) { $serviceParams.InstanceName = $InstanceName }
            if ($Type) { $serviceParams.Type = $Type }
            if ($Credential) { $serviceParams.Credential = $Credential }
            if ($EnableException) { $serviceParams.Silent = $EnableException }
            $serviceCollection = Get-DbaSqlService @serviceParams
        }
    }
    process {
        #Get all the objects from the pipeline before proceeding
        $processArray += $serviceCollection
    }
    end {
        $processArray = $processArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.ServiceType -in $Type) }
        if ($processArray) {
            Update-ServiceStatus -ServiceCollection $processArray -Action 'start' -Timeout $Timeout -EnableException $EnableException
        }
        else { Write-Message -Level Warning -EnableException $EnableException -Message "No SQL Server services found with current parameters." }
    }
}
