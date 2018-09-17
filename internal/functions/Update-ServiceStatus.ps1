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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object[]]$InputObject,
        [parameter(Mandatory = $true)]
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
            param (
                $server,
                $service,
                $action,
                $timeout,
                [System.Management.Automation.PSCredential]
                $credential
            )

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
                $svc = Get-DbaCmObject -ComputerName $server -Namespace "root\cimv2" -query "SELECT * FROM Win32_Service WHERE name = '$service'" -Credential $credential
            }
            catch {
                throw $_
                break
            }
            #Invoke corresponding CIM method
            $x = Invoke-CimMethod -InputObject $svc -MethodName $methodName

            $result = [psobject](@{} | Select-Object ExitCode, ServiceState)
            #If command was not accepted
            if ($x.ReturnValue -ne 0) {
                $result.ExitCode = $x.ReturnValue
                $result.ServiceState = $svc.State
            }
            else {
                $startTime = Get-Date
                #Wait for the service to complete the action until timeout
                while ($true) {
                    try {
                        $svc = Get-DbaCmObject -ComputerName $server -Namespace "root\cimv2" -query "SELECT State FROM Win32_Service WHERE name = '$service'" -Credential $credential
                    }
                    catch {
                        throw $_
                        break
                    }
                    $result.ServiceState = $svc.State
                    #Succeeded
                    if ($svc.State -eq $desiredState) { $result.ExitCode = 0; break }
                    #Failed after being in the Pending state
                    if ($pending -and $svc.State -eq $undesiredState) { $result.ExitCode = -2; break }
                    #Timed out
                    if ($timeout -gt 0 -and ((Get-Date) - $startTime).TotalSeconds -gt $timeout) { $result.ExitCode = -1; break}
                    #Still pending
                    if ($svc.State -like '*Pending') { $pending = $true }
                    Start-Sleep -Milliseconds 100
                }
            }
            $result
        }

        $actionText = switch ($action) { stop { 'stopped' }; start { 'started' }; restart { 'restarted' } }
        #Setup initial session state
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $InitialSessionState.ImportPSModule((get-module dbatools).modulebase + '\dbatools.psd1')
        #Create Runspace pool, min - 1, max - 50 sessions
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, 50, $InitialSessionState, $Host)
        $runspacePool.Open()
    }

    process {
        $threads = @()

        #Get priorities on which the service startup/shutdown order is based
        $servicePriorityCollection = $InputObject.ServicePriority | Select-Object -unique | Sort-Object -Property @{ Expression = { [int]$_ }; Descending = $action -ne 'stop' }
        foreach ($priority in $servicePriorityCollection) {
            foreach ($service in ($InputObject | Where-Object { $_.ServicePriority -eq $priority })) {
                if ('dbatools.DbaSqlService' -in $service.PSObject.TypeNames) {
                    if (($service.State -eq 'Running' -and $action -eq 'start') -or ($service.State -eq 'Stopped' -and $action -eq 'stop')) {
                        Add-Member -Force -InputObject $service -NotePropertyName Status -NotePropertyValue 'Successful'
                        Add-Member -Force -InputObject $service -NotePropertyName Message -NotePropertyValue "The service is already $actionText, no action required"
                        Select-DefaultView -InputObject $service -Property ComputerName, ServiceName, State, Status, Message
                    }
                    elseif ($service.StartMode -eq 'Disabled' -and $action -in 'start', 'restart') {
                        Add-Member -Force -InputObject $service -NotePropertyName Status -NotePropertyValue 'Failed'
                        Add-Member -Force -InputObject $service -NotePropertyName Message -NotePropertyValue "The service is disabled and cannot be $actionText"
                        Select-DefaultView -InputObject $service -Property ComputerName, ServiceName, State, Status, Message
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess("Sending $action request to service $($service.ServiceName) on $($service.ComputerName)")) {
                            #Create parameters hashtable
                            $argsRunPool = @{
                                server     = $service.computerName
                                service    = $service.ServiceName
                                action     = $action
                                timeout    = $Timeout
                                credential = $Credential
                            }
                            Write-Message -Level Verbose -Message "Sending $action request to service $($service.ServiceName) on $($service.ComputerName) with timeout $Timeout"
                            #Create new runspace thread
                            $thread = [powershell]::Create()
                            $thread.RunspacePool = $runspacePool
                            $thread.AddScript($svcControlBlock) | Out-Null
                            $thread.AddParameters($argsRunPool) | Out-Null
                            #Start the thread
                            $handle = $thread.BeginInvoke()
                            $threads += [pscustomobject]@{
                                handle       = $handle
                                thread       = $thread
                                serviceName  = $service.ServiceName
                                computerName = $service.ComputerName
                                isRetrieved  = $false
                                started      = Get-Date
                            }
                        }
                    }
                }
                else {
                    Stop-Function -FunctionName $callerName -Message "Unknown object in pipeline - make sure to use Get-DbaSqlService cmdlet" -EnableException $EnableException
                    Return
                }
            }
            if ($Pscmdlet.ShouldProcess("Waiting for the services to $action")) {
                #Get job execution results
                while ($threads | Where-Object { $_.isRetrieved -eq $false }) {
                    foreach ($thread in ($threads | Where-Object { $_.isRetrieved -eq $false })) {
                        if ($thread.Handle.IsCompleted -eq $true) {
                            Write-Message -Level Verbose -Message "Processing runspace thread results from service $($thread.ServiceName) on $($thread.ComputerName)"
                            $jobResult = $null
                            try {
                                $jobResult = $thread.thread.EndInvoke($thread.handle)
                            }
                            catch {
                                $jobError = $_
                                Write-Message -Level Verbose -Message ("Could not return data from the runspace thread: " + $_.Exception.Message)
                            }
                            $thread.isRetrieved = $true
                            if ($thread.thread.HadErrors) {
                                if (!$jobError) { $jobError = $thread.thread.Streams.Error }
                                Stop-Function -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to $action the service $($thread.ServiceName) on $($thread.ComputerName) returned the following error: " + ($jobError.Exception.Message -join ' ')) -Category ConnectionError -ErrorRecord $thread.thread.Streams.Error -Target $thread -Continue
                            }
                            elseif (!$jobResult) {
                                Stop-Function -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to $action the service $($thread.ServiceName) on $($thread.ComputerName) did not return any results") -Category ConnectionError -ErrorRecord $_ -Target $thread -Continue
                            }
                            #Find a corresponding service object
                            $outObject = $InputObject | Where-Object { $_.ServiceName -eq $thread.serviceName -and $_.ComputerName -eq $thread.computerName }
                            #Set additional properties
                            $status = switch ($jobResult.ExitCode) {
                                0 { 'Successful' }
                                10 { 'Successful '} #Already running - FullText service is started automatically
                                default { 'Failed' }
                            }
                            Add-Member -Force -InputObject $outObject -NotePropertyName Status -NotePropertyValue $status
                            $message = switch ($jobResult.ExitCode) {
                                -2 { "The service failed to $action." }
                                -1 { "The attempt to $action the service has timed out." }
                                0 { "Service was successfully $actionText." }
                                default { "The attempt to $action the service returned the following error: " + (Get-DBASQLServiceErrorMessage $jobResult.ExitCode) }
                            }
                            Add-Member -Force -InputObject $outObject -NotePropertyName Message -NotePropertyValue $message
                            if ($jobResult.ServiceState) { $outObject.State = $jobResult.ServiceState }
                            #Dispose of the thread
                            $thread.thread.Dispose()

                            Select-DefaultView -InputObject $outObject -Property ComputerName, ServiceName, State, Status, Message
                        }
                        elseif ($Timeout -gt 0 -and ((Get-Date) - $thread.started).TotalSeconds -gt $Timeout) {
                            #Session has timed out - return failure and stop the thread

                            $thread.isRetrieved = $true
                            $outObject = $InputObject | Where-Object { $_.ServiceName -eq $thread.serviceName -and $_.ComputerName -eq $thread.computerName }
                            #Set additional properties
                            Add-Member -Force -InputObject $outObject -NotePropertyName Status -NotePropertyValue 'Failed'
                            Add-Member -Force -InputObject $outObject -NotePropertyName Message -NotePropertyValue "The attempt to $action the service has timed out."
                            $outObject.State = 'Unknown'
                            #Stop and dispose of the thread
                            $thread.thread.Stop()
                            $thread.thread.Dispose()

                            Select-DefaultView -InputObject $outObject -Property ComputerName, ServiceName, State, Status, Message
                        }
                    }
                    Start-Sleep -Milliseconds 50
                }
            }
        }
    }
    end {
        #Close the runspace pool
        $runspacePool.Close()
    }
}
