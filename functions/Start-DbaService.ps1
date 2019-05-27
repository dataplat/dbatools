function Start-DbaService {
    <#
    .SYNOPSIS
        Starts SQL Server services on a computer.

    .DESCRIPTION
        Starts the SQL Server related services on one or more computers. Will follow SQL Server service dependencies.

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
        [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS")]
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
                Update-ServiceStatus -InputObject $processArray -Action 'start' -Timeout $Timeout -EnableException $EnableException
            } else {
                Stop-Function -EnableException $EnableException -Message "No SQL Server services found with current parameters." -Category ObjectNotFound
            }
        }
    }
}