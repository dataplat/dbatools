function Update-ServiceStatus {
    <#
    .SYNOPSIS
        Internal function. Sends start/stop request to a SQL Server service and wait for the result.

    .DESCRIPTION
        Accepts objects from Get-DbaService and performs a corresponding action.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Timeout
        How long to wait for the start/stop request completion before moving on.

    .PARAMETER InputObject
        A collection of services from Get-DbaService

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
       Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        $InputObject = Get-DbaService -ComputerName sql1
        Update-ServiceStatus -InputObject $InputObject -Action 'stop' -Timeout 30
        Update-ServiceStatus -InputObject $InputObject -Action 'start' -Timeout 30

        Restarts SQL services on sql1

    .EXAMPLE
        $InputObject = Get-DbaService -ComputerName sql1
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
        [int]$Timeout = 60,
        [PSCredential] $Credential,
        [bool]$EnableException
    )
    begin {
        $callStack = Get-PSCallStack
        if ($callStack.Length -gt 1) {
            $callerName = $callStack[1].Command
        } else {
            $callerName = $callStack[0].Command
        }
        #Prepare the service control script block
        $svcControlBlock = {
            $group = $_.Group
            $computerName = $_.Name
            $servicePriorityCollection = $group.ServicePriority | Select-Object -unique | Sort-Object -Property @{ Expression = { [int]$_ }; Descending = $action -ne 'stop' }
            foreach ($priority in $servicePriorityCollection) {
                $services = $group | Where-Object { $_.ServicePriority -eq $priority }
                $servicesToRestart = @()
                foreach ($service in $services) {
                    if ('dbatools.DbaSqlService' -in $service.PSObject.TypeNames) {
                        $cimObject = $service._CimObject
                        if (($cimObject.State -eq 'Running' -and $action -eq 'start') -or ($cimObject.State -eq 'Stopped' -and $action -eq 'stop')) {
                            $service | Add-Member -Force -NotePropertyName Status -NotePropertyValue 'Successful' -PassThru |
                            Add-Member -Force -NotePropertyName Message -NotePropertyValue "The service is already $actionText, no action required" -PassThru
                    } elseif ($cimObject.StartMode -eq 'Disabled' -and $action -in 'start', 'restart') {
                        $service | Add-Member -Force -NotePropertyName Status -NotePropertyValue 'Failed' -PassThru |
                        Add-Member -Force -NotePropertyName Message -NotePropertyValue "The service is disabled and cannot be $actionText" -PassThru
                } else {
                    $servicesToRestart += $service
                }
            } else {
                throw "Unknown object in pipeline - make sure to use Get-DbaService cmdlet"
            }
        }
        #Set desired $action
        if ($action -in 'start', 'restart') {
            $methodName = 'StartService'
            $desiredState = 'Running'
            $undesiredState = 'Stopped'
        } elseif ($action -eq 'stop') {
            $methodName = 'StopService'
            $desiredState = 'Stopped'
            $undesiredState = 'Running'
        }
        $invokeResults = @()
        foreach ($service in $servicesToRestart) {
            if ($Pscmdlet.ShouldProcess("Sending $action request to service $($service.ServiceName) on $($service.ComputerName)")) {
                #Invoke corresponding CIM method
                $invokeResult = Invoke-CimMethod -InputObject $service._CimObject -MethodName $methodName
                $invokeResults += [psobject]@{
                    InvokeResult    = $invokeResult
                    ServiceState    = $invokeResult.State
                    ServiceExitCode = $invokeResult.ReturnValue
                    CheckPending    = $true
                    Service         = $service
                }
            }
        }

        $startTime = Get-Date
        if ($Pscmdlet.ShouldProcess("Waiting the services to $action on $computerName")) {
            #Wait for the service to complete the action until timeout
            while ($invokeResults.CheckPending -contains $true) {
                foreach ($result in ($invokeResults | Where-Object CheckPending -eq $true)) {
                    try {
                        #Refresh Cim instance - not using Get-DbaCmObject because module is not loaded here, but it only refreshes existing object
                        $result.Service._CimObject = $result.Service._CimObject | Get-CimInstance
                    } catch {
                        $result.ServiceExitCode = -3
                        $result.ServiceState = 'Unknown'
                        $result.CheckPending = $false
                        continue
                    }
                    $result.ServiceState = $result.Service._CimObject.State
                    #Failed or succeeded
                    if ($result.ServiceExitCode -ne 0 -or $result.ServiceState -eq $desiredState) {
                        $result.CheckPending = $false
                        continue
                    }
                    #Failed after being in the Pending state
                    if ($result.CheckPending -and $result.ServiceState -eq $undesiredState) {
                        $result.ServiceExitCode = -2
                        $result.CheckPending = $false
                        continue
                    }
                    #Timed out
                    if ($timeout -gt 0 -and ((Get-Date) - $startTime).TotalSeconds -gt $timeout) {
                        $result.ServiceExitCode = -1
                        $result.CheckPending = $false
                        continue
                    }
                    #Still pending - leave CheckPending as is and run again
                }
                Start-Sleep -Milliseconds 200
            }
        }
        foreach ($result in $invokeResults) {
            #Add status
            $status = switch ($result.ServiceExitCode) {
                0 { 'Successful' }
                10 { 'Successful ' } #Already running - FullText service is started automatically
                default { 'Failed' }
            }
            Add-Member -Force -InputObject $result.Service -NotePropertyName Status -NotePropertyValue $status
            #Add error message
            $errorMessageFromReturnValue = if ($result.ServiceExitCode -in 0..($errorCodes.Length - 1)) {
                $errorCodes[$result.ServiceExitCode]
            } else { "Unknown error." }
            $message = switch ($result.ServiceExitCode) {
                -2 { "The service failed to $action." }
                -1 { "The attempt to $action the service has timed out." }
                0 { "Service was successfully $actionText." }
                default { "The attempt to $action the service returned the following error: $errorMessageFromReturnValue" }
            }
            Add-Member -Force -InputObject $result.Service -NotePropertyName Message -NotePropertyValue $message
            # Refresh service state for the object
            if ($result.ServiceState) { $result.Service.State = $result.ServiceState }
            $result
        }
    }
}

$actionText = switch ($action) { stop { 'stopped' }; start { 'started' }; restart { 'restarted' } }
$errorCodes = Get-DbaServiceErrorMessage
}

process {
    #Group services for each computer
    $serviceComputerGroup = $InputObject | Group-Object -Property ComputerName
    foreach ($group in $serviceComputerGroup) {
        Write-Message -Message "Getting CIM objects from computer $($group.Name)"
        $serviceNames = $group.Group.ServiceName -join "' OR name = '"
        try {
            $svcCim = Get-DbaCmObject -ComputerName $group.Name -Namespace "root\cimv2" -query "SELECT * FROM Win32_Service WHERE name = '$serviceNames'" -Credential $credential
        } catch {
            Stop-Function -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to get CIM session for the services on $($group.Name) returned the following error: " + ($_.Exception.Message -join ' ')) -Category ConnectionError -ErrorRecord $_
        }
        foreach ($service in $group.Group) {
            if ($cimObject = ($svcCim | Where-Object Name -eq $service.ServiceName)) {
                Add-Member -Force -InputObject $service -NotePropertyName _CimObject -NotePropertyValue $cimObject
            } else {
                Stop-Function -Message "Failed to retrieve service name $($service.ServiceName) from the CIM object collection - the service will not be processed" -Continue -Target $group.Name
            }
        }
    }
    if ($Pscmdlet.ShouldProcess("Running the following service action: $action")) {
        if ($serviceComputerGroup) {
            try {
                $serviceComputerGroup | Invoke-Parallel -ScriptBlock $svcControlBlock -Throttle 50 -ImportVariables | ForEach-Object {
                    if ($_.ServiceExitCode) {
                        $target = "$($_.Service.ServiceName) on $($_.Service.ComputerName)"
                        Write-Message -Level Warning -Message "($target) $($_.Service.Message)" -Target $target
                        if ($_.Service.ServiceType -eq 'Engine' -and $_.ServiceExitCode -eq 3) {
                            Write-Message -Level Warning -Message "($target) Run the command with '-Force' switch to force the restart of a dependent SQL Agent" -Target $target
                        }
                    }
                    $_.Service | Select-DefaultView -Property ComputerName, ServiceName, InstanceName, ServiceType, State, Status, Message
                }
            } catch {
                Stop-Function -Message "Multi-threaded execution returned an error" -ErrorRecord $_ -EnableException $EnableException -FunctionName $callerName
            }
        }
    }
}
end {
}
}