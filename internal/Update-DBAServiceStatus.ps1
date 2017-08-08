Function Update-DBASqlServiceStatus {
<#
    .SYNOPSIS
    Internal function. Sends start/stop request to a SQL Server service.

    .DESCRIPTION
    Accepts objects from Get-DBASqlService and performs a corresponding action.

    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.

    .PARAMETER Timeout
    How long to wait for the start/stop request completion before moving on.
    
    .PARAMETER ServiceCollection
    A collection of services from Get-DBASqlService
    
    .PARAMETER Action
    Start or stop.
    
    .PARAMETER Silent
    Supress all the output from the function.

    .NOTES
    Author: Kirill Kravtsov ( @nvarscar )

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

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
			$timeout = 30,
			$credential
			)
			#Get WMI service object
			$svcParam = "name='$service'"
			$svc = Get-WmiObject Win32_Service -ComputerName $server -filter $svcParam -Credential $credential
			#Perform $action
			if ($action -eq 'start') { 
				$x = $svc.StartService() 
				$desiredState = 'Running'
				$undesiredState = 'Stopped'
			}
			elseif ($action -eq 'stop') { 
				$x = $svc.StopService() 
				$desiredState = 'Stopped'
				$undesiredState = 'Running'
			}
			#If command was not accepted
			if ($x.ReturnValue -ne 0) {return $x.ReturnValue}
			$StartTime = Get-Date
			#Wait for the service to complete the action until timeout
			while ($true -and $x.ReturnValue -eq 0) {
				try {
					$svc = Get-WmiObject Win32_Service -ComputerName $server -filter $svcParam -Credential $credential
				}
				catch {
					throw $_
					break
				}
				#Succeeded
				if ($svc.State -eq $desiredState) { return 0 }
				#Failed after being in the Pending state
				if ($pending -and $svc.State -eq $undesiredState) { return -2 }
				#Timed out
				if ($timeout -gt 0 -and ((Get-Date) - $StartTime).TotalSeconds -gt $timeout) { 
					return -1
				}
				#Still pending
				if ($svc.State -like '*Pending') { $pending = $true }
				start-sleep 1
			}
		}
	}
	
	process {
		$jobCollection = @()
		#Get priorities on which the service startup/shutdown order is based
		$servicePriorityCollection = $ServiceCollection.ServicePriority | Select-Object -unique | Sort-Object -Property @{Expression={[int]$_}; Descending = $action -eq 'start'}
		foreach ($priority in $servicePriorityCollection) {
			foreach ($service in ($ServiceCollection | Where-Object { $_.ServicePriority -eq $priority }) ) {
				if ('dbatools.DbaSqlService' -in $service.PSObject.TypeNames) {
					if ($Pscmdlet.ShouldProcess("Sending $action request to service $($service.ServiceName) on $($service.ComputerName)")) {
						Write-Message -Level Verbose -Message "Attempting to $action service $($service.ServiceName) on $server."
						#Start a job per each service 
						$job = Start-Job -ScriptBlock $svcControlBlock -ArgumentList $service.computerName, $service.ServiceName, $action, $Timeout, $credential
						#Add more properties to the job so that we could distinct them
						Add-Member -Force -InputObject $job -NotePropertyName ServiceName -NotePropertyValue $service.ServiceName
						Add-Member -Force -InputObject $job -NotePropertyName ComputerName -NotePropertyValue $service.ComputerName
						$jobCollection += $job
					}
				}
				else {
					Write-Message -Level Critical -Message "Unknown object in pipeline - make sure to use Get-DBAService cmdlet"
				}
			}
	    if ($Pscmdlet.ShouldProcess("Waiting for the services to $action")) {
	    	#Get job execution results
		    while ($jobCollection | where { $_.HasMoreData -eq $true }) {
			    foreach ($job in ($jobCollection | where { $_.State -ne "Running" -and $_.HasMoreData -eq $true })) {
			    	try {
			    		$jobResult = $job | Receive-Job -ErrorAction Stop
				    	switch ($jobResult) {
				    		-2 { Write-Message -Level Warning -Silent $Silent -FunctionName $callerName -Message "The service $($job.ServiceName) on $($job.ComputerName) failed to $action." }
				    		-1 { Write-Message -Level Warning -Silent $Silent -FunctionName $callerName -Message "The attempt to $action the service $($job.ServiceName) on $($job.ComputerName) has timed out." }
				    		0 { switch ($action) { stop { $actionText = 'stopped' }; start { $actionText = 'started' } } 
				    			Write-Message -Level Output -Silent $Silent -FunctionName $callerName -Message "Service $($job.ServiceName) on $($job.ComputerName) was successfully $actionText." 
				    		}
				    		default { Write-Message -Level Warning -Silent $Silent -FunctionName $callerName -Message ("The attempt to $action the service $($job.ServiceName) on $($job.ComputerName) returned the following error: " + (Get-DBASQLServiceErrorMessage $jobResult))}
				    	}
				    }
				    catch {
				    	Write-Message -Level Warning -Silent $Silent -FunctionName $callerName -Message ("The attempt to $action the service $($job.ServiceName) on $($job.ComputerName) returned the following error: " + $_.Exception.Message)
				    }
			    }
			    Start-Sleep -Milliseconds 50
			  }
			}
		}
	}
}