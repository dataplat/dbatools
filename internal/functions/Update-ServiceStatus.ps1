function Update-ServiceStatus {
    <#
    .SYNOPSIS
        Internal function. Sends start/stop request to a SQL Server service and wait for the result.

    .DESCRIPTION
        Accepts objects from Get-DbaSqlService and performs a corresponding action.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Timeout
        How long to wait for the start/stop request completion before moving on.

    .PARAMETER InputObject
        A collection of services from Get-DbaSqlService

    .PARAMETER Action
        Start or stop.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Author: Kirill Kravtsov ( @nvarscar )
        Tags:
        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2016 Chrissy LeMaire
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        $InputObject = Get-DbaSqlService -ComputerName sql1
        Update-ServiceStatus -InputObject $InputObject -Action 'stop' -Timeout 30
        Update-ServiceStatus -InputObject $InputObject -Action 'start' -Timeout 30

        Restarts SQL services on sql1

    .EXAMPLE
        $InputObject = Get-DbaSqlService -ComputerName sql1
        $credential = Get-Credential
        Update-ServiceStatus -InputObject $InputObject -Action 'stop' -Timeout 0 -Credential $credential

        Stops SQL services on sql1 and waits indefinitely for them to stop. Uses $credential to authorize on the server.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [parameter(ValueFromPipeline, Mandatory)]
        [object[]]$InputObject,
        [parameter(Mandatory)]
        [string[]]$Action,
        [int]$Timeout = 30,
        [PSCredential] $Credential,
        [bool][Alias('Silent')]$EnableException
    )
    begin {
        $callStack = Get-PSCallStack
        if ($callStack.Length -gt 1) {
            $callerName = $callStack[1].Command
        }
        else {
            $callerName = $callStack[0].Command
        }
        #Prepare the service control script block
        $svcControlBlock = {
            if ('dbatools.DbaSqlService' -in $_.PSObject.TypeNames) {
                if (($_.State -eq 'Running' -and $action -eq 'start') -or ($_.State -eq 'Stopped' -and $action -eq 'stop')) {
                    Add-Member -Force -InputObject $_ -NotePropertyName Status -NotePropertyValue 'Successful'
                    Add-Member -Force -InputObject $_ -NotePropertyName Message -NotePropertyValue "The service is already $actionText, no action required"
                    Select-DefaultView -InputObject $_ -Property ComputerName, ServiceName, State, Status, Message
                }
                elseif ($_.StartMode -eq 'Disabled' -and $action -in 'start', 'restart') {
                    Add-Member -Force -InputObject $_ -NotePropertyName Status -NotePropertyValue 'Failed'
                    Add-Member -Force -InputObject $_ -NotePropertyName Message -NotePropertyValue "The service is disabled and cannot be $actionText"
                    Select-DefaultView -InputObject $_ -Property ComputerName, ServiceName, State, Status, Message
                }
                else {
                    if ($Pscmdlet.ShouldProcess("Sending $action request to service $($_.ServiceName) on $($_.ComputerName)")) {
                        #Perform $action
                        if ($action -in 'start', 'restart') {
                            $methodName = 'StartService'
                            $desiredState = 'Running'
                            $undesiredState = 'Stopped'
                        }
                        elseif ($action -eq 'stop') {
                            $methodName = 'StopService'
                            $desiredState = 'Stopped'
                            $undesiredState = 'Running'
                        }
                        #Get CIM object
                        try {
                            $svc = Get-DbaCmObject -ComputerName $_.ComputerName -Namespace "root\cimv2" -query "SELECT * FROM Win32_Service WHERE name = '$($_.ServiceName)'" -Credential $credential
                        }
                        catch {
                            Stop-Function -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to $action the service $($_.ServiceName) on $($thread.ComputerName) returned the following error: " + ($_.Exception.Message -join ' ')) -Category ConnectionError -ErrorRecord $_
                            Return
                        }
                        #Invoke corresponding CIM method
                        $invokeResult = Invoke-CimMethod -InputObject $svc -MethodName $methodName
                        $serviceState = $invokeResult.State
                        $serviceExitCode = $invokeResult.ReturnValue

                        $startTime = Get-Date
                        #Wait for the service to complete the action until timeout
                        while ($true) {
                            try {
                                $svc = Get-DbaCmObject -ComputerName $_.ComputerName -Namespace "root\cimv2" -query "SELECT State FROM Win32_Service WHERE name = '$($_.ServiceName)'" -Credential $credential
                            }
                            catch {
                                Stop-Function -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to $action the service $($_.ServiceName) on $($_.ComputerName) returned the following error: " + ($_.Exception.Message -join ' ')) -Category ConnectionError -ErrorRecord $_
                                Return
                            }
                            $serviceState = $svc.State
                            #Succeeded
                            if ($svc.State -eq $desiredState) { break }
                            #Failed after being in the Pending state
                            if ($pending -and $svc.State -eq $undesiredState) { $serviceExitCode = -2; break }
                            #Timed out
                            if ($timeout -gt 0 -and ((Get-Date) - $startTime).TotalSeconds -gt $timeout) { $serviceExitCode = -1; break}
                            #Still pending
                            if ($svc.State -like '*Pending') { $pending = $true }
                            Start-Sleep -Milliseconds 200
                        }
                        $outObject = $_
                        #Set additional properties
                        $status = switch ($serviceExitCode) {
                            0 { 'Successful' }
                            10 { 'Successful '} #Already running - FullText service is started automatically
                            default { 'Failed' }
                        }
                        Add-Member -Force -InputObject $outObject -NotePropertyName Status -NotePropertyValue $status
                        $message = switch ($serviceExitCode) {
                            -2 { "The service failed to $action." }
                            -1 { "The attempt to $action the service has timed out." }
                            0 { "Service was successfully $actionText." }
                            default { "The attempt to $action the service returned the following error: " + (Get-DBASQLServiceErrorMessage $invokeResult.ReturnValue) }
                        }
                        Add-Member -Force -InputObject $outObject -NotePropertyName Message -NotePropertyValue $message
                        if ($serviceState) { $outObject.State = $serviceState }

                        $outObject
                    }
                }
            }
            else {
                Stop-Function -FunctionName $callerName -Message "Unknown object in pipeline - make sure to use Get-DbaSqlService cmdlet" -EnableException $EnableException
                Return
            }
        }

        $actionText = switch ($action) { stop { 'stopped' }; start { 'started' }; restart { 'restarted' } }
    }

    process {
        #Get priorities on which the service startup/shutdown order is based
        $servicePriorityCollection = $InputObject.ServicePriority | Select-Object -unique | Sort-Object -Property @{ Expression = { [int]$_ }; Descending = $action -ne 'stop' }
        foreach ($priority in $servicePriorityCollection) {
            $services =  $InputObject | Where-Object { $_.ServicePriority -eq $priority }
            if ($Pscmdlet.ShouldProcess("Running the following service action: $action")) {
                $services |
                Invoke-Parallel -ScriptBlock $svcControlBlock -RunspaceTimeout $Timeout -Throttle 50 -ImportVariables -ImportModules |
                Select-DefaultView -Property ComputerName, ServiceName, State, Status, Message
            }
        }
    }
    end {
    }
}
