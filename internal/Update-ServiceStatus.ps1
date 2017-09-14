Function Update-ServiceStatus {
	<#
    .SYNOPSIS
    Internal function. Sends start/stop request to a SQL Server service and wait for the result.

    .DESCRIPTION
    Accepts objects from Get-DbaSqlService and performs a corresponding action.

    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.

    .PARAMETER Timeout
    How long to wait for the start/stop request completion before moving on.
    
    .PARAMETER ServiceCollection
    A collection of services from Get-DbaSqlService
    
    .PARAMETER Action
    Start or stop.
    
    .PARAMETER Silent
    Use this switch to disable any kind of verbose messages
		
		.PARAMETER WhatIf
		Shows what would happen if the cmdlet runs. The cmdlet is not run.
		
		.PARAMETER Confirm
		Prompts you for confirmation before running the cmdlet.

    .NOTES
    Author: Kirill Kravtsov ( @nvarscar )

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
    
    .EXAMPLE
    $serviceCollection = Get-DbaSqlService -ComputerName sql1
    Update-ServiceStatus -ServiceCollection $serviceCollection -Action 'stop' -Timeout 30
    Update-ServiceStatus -ServiceCollection $serviceCollection -Action 'start' -Timeout 30
    
    Restarts SQL services on sql1
    
    .EXAMPLE
    $serviceCollection = Get-DbaSqlService -ComputerName sql1
    $credential = Get-Credential
    Update-ServiceStatus -ServiceCollection $serviceCollection -Action 'stop' -Timeout 0 -Credential $credential
    
    Stops SQL services on sql1 and waits indefinitely for them to stop. Uses $credential to authorize on the server.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param(
		[parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[object[]]$ServiceCollection,
		[parameter(Mandatory = $true)]
		[string[]]$Action,
		[int]$Timeout = 30,
		[PSCredential] $Credential,
		[bool]$Silent
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
			Param (
				$server,
				$service,
				$action,
				$timeout,
				$credential
			)
			
			#Perform $action
			$svcPath = "Win32_Service.Name='$service'"
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
			$x = Invoke-WmiMethod -path $svcPath -name $methodName -ComputerName $server -Credential $credential
			$result = [psobject](@{} | Select-Object ExitCode, ServiceState)
			#If command was not accepted
			if ($x.ReturnValue -ne 0) { 
				try {
					$svc = Get-DbaCmObject -ComputerName $server -Namespace "root\cimv2" -query "SELECT State FROM Win32_Service WHERE name = '$service'" -Credential $credential
				}
				catch {
					throw $_
					break
				}
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
					if ($timeout -gt 0 -and ((Get-Date) - $startTime).TotalSeconds -gt $timeout) { $result.ExitCode = -1; break	}
					#Still pending
					if ($svc.State -like '*Pending') { $pending = $true }
					Start-Sleep -Milliseconds 100
				}
			}
			$result
		}

		$actionText = switch ($action) { stop { 'stopped' }; start { 'started' }; restart { 'restarted' } } 
	}
	
	process {
		$jobCollection = @()
		#Get priorities on which the service startup/shutdown order is based
		$servicePriorityCollection = $ServiceCollection.ServicePriority | Select-Object -unique | Sort-Object -Property @{ Expression = { [int]$_ }; Descending = $action -ne 'stop' }
		foreach ($priority in $servicePriorityCollection) {
			foreach ($service in ($ServiceCollection | Where-Object { $_.ServicePriority -eq $priority })) {
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
							#Start a job per each service 
							Write-Message -Level Verbose -Message "Sending $action request to service $($service.ServiceName) on $($service.ComputerName) with timeout $Timeout"
							$job = Start-Job -ScriptBlock $svcControlBlock -ArgumentList $service.computerName, $service.ServiceName, $action, $Timeout, $credential
							#Add more properties to the job so that we could distinct them
							Add-Member -Force -InputObject $job -NotePropertyName ServiceName -NotePropertyValue $service.ServiceName
							Add-Member -Force -InputObject $job -NotePropertyName ComputerName -NotePropertyValue $service.ComputerName
							$jobCollection += $job
						}
					}
				}
				else {
					Stop-Function -FunctionName $callerName -Message "Unknown object in pipeline - make sure to use Get-DbaSqlService cmdlet" -Silent $Silent
					Return
				}
			}
			if ($Pscmdlet.ShouldProcess("Waiting for the services to $action")) {
				#Get job execution results
				while ($jobCollection | Where-Object { $_.HasMoreData -eq $true }) {
					foreach ($job in ($jobCollection | Where-Object { $_.State -ne "Running" -and $_.HasMoreData -eq $true })) {
						try {
							$jobResult = $job | Receive-Job -ErrorAction Stop
							#Find a corresponding service object
							$outObject = $ServiceCollection | Where-Object { $_.ServiceName -eq $job.ServiceName -and $_.ComputerName -eq $job.ComputerName }
							$status = switch ($jobResult.ExitCode) {
								0 { 'Successful' }
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
							Select-DefaultView -InputObject $outObject -Property ComputerName, ServiceName, State, Status, Message
						}
						catch {
							Stop-Function -Silent $Silent -FunctionName $callerName -Message ("The attempt to $action the service $($job.ServiceName) on $($job.ComputerName) returned the following error: " + $_.Exception.Message) -Category ConnectionError -ErrorRecord $_ -Target $job -Continue
						}
					}
					Start-Sleep -Milliseconds 50
				}
			}
		}
	}
}
