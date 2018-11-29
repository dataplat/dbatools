function Set-ServiceStartMode {
    <#
        .SYNOPSIS
        Internal function. Implements the method that changes startup mode of the SQL Server service.

        .DESCRIPTION
        Accepts objects from Get-DbaService and performs a corresponding action.

        .PARAMETER InputObject
        A collection of services from Get-DbaService.

        .PARAMETER Mode
        Startup mode of the service: Automatic, Manual or Disabled.

        .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

        .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

        .NOTES
        Author: Kirill Kravtsov ( @nvarscar )

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
        Get-DbaService -ComputerName sql1 | Set-ServiceStartMode -Mode 'Manual'

        Sets all SQL services on sql1 to Manual startup.

        .EXAMPLE
        $services = Get-DbaService -ComputerName sql1
        Set-ServiceStartMode -InputObject $services -Mode 'Automatic'

        Sets all SQL services on sql1 to Automatic startup.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$Mode,
        [parameter(ValueFromPipeline, Mandatory)]
        [object[]]$InputObject
    )
    begin {
        $callStack = Get-PSCallStack
        if ($callStack.Length -gt 1) {
            $callerName = $callStack[1].Command
        } else {
            $callerName = $callStack[0].Command
        }
        $ProcessArray = @()
    }
    process {
        #Get all the objects from the pipeline before proceeding
        $ProcessArray += $InputObject
    }
    end {
        foreach ($service in $ProcessArray) {
            #Get WMI object
            $Wmi = Get-DbaCmObject -ComputerName $service.ComputerName -Namespace "root\cimv2" -Query "SELECT * FROM Win32_Service WHERE Name = '$($service.ServiceName)'" -EnableException
            if ($Pscmdlet.ShouldProcess($Wmi, "Changing the Start Mode to $Mode")) {
                $x = $Wmi | Invoke-CimMethod -MethodName ChangeStartMode -Arguments @{ StartMode = $Mode }
                if ($x.ReturnValue -ne 0) {
                    Stop-Function -EnableException $EnableException -Message ("The attempt to change the start mode of $($service.ServiceName) on $($service.ComputerName) returned the following message: " + (Get-DbaServiceErrorMessage $x.ReturnValue))
                    return
                }
            }
        }
    }
}