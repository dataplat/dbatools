function Set-ServiceStartMode {
    <#
        .SYNOPSIS
        Internal function. Implements the method that changes startup mode of the SQL Server service.

        .DESCRIPTION
        Accepts objects from Get-DbaSqlService and performs a corresponding action.

        .PARAMETER ServiceCollection
        A collection of services from Get-DbaSqlService.

        .PARAMETER Mode
        Startup mode of the service: Automatic, Manual or Disabled.

        .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

        .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

        .NOTES
        Author: Kirill Kravtsov ( @nvarscar )

        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2017 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .EXAMPLE
        Get-DbaSqlService -ComputerName sql1 | Set-ServiceStartMode -Mode 'Manual'

        Sets all SQL services on sql1 to Manual startup.

        .EXAMPLE
        $services = Get-DbaSqlService -ComputerName sql1
        Set-ServiceStartMode -ServiceCollection $services -Mode 'Automatic'

        Sets all SQL services on sql1 to Automatic startup.

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string]$Mode,
        [parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object[]]$ServiceCollection
    )
    begin {
        $callStack = Get-PSCallStack
        if ($callStack.Length -gt 1) {
            $callerName = $callStack[1].Command
        }
        else {
            $callerName = $callStack[0].Command
        }
        $ProcessArray = @()
    }
    process {
        #Get all the objects from the pipeline before proceeding
        $ProcessArray += $ServiceCollection
    }
    end {
        $ProcessArray = $ProcessArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.type -in $Type) }
        foreach ($service in $ProcessArray) {
            #Get WMI object
            $Wmi = Get-WmiObject Win32_Service -ComputerName $service.ComputerName -filter "name='$($service.ServiceName)'"
            if ($Pscmdlet.ShouldProcess($Wmi, "Changing the Start Mode to $Mode")) {
                $x = $Wmi.ChangeStartMode($Mode)
                if ($x.ReturnValue -ne 0) {
                    Write-Message -Level Warning -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to $action the service $($job.ServiceName) on $($job.ComputerName) returned the following message: " + (Get-DbaSQLServiceErrorMessage $x.ReturnValue))
                }
            }
        }
    }
}