#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Test-ElevationRequirement {
	<#
		.SYNOPSIS
			Command that tests, whether the process runs elevated and has to run as such.
		
		.DESCRIPTION
			Command that tests, whether the process runs elevated and has to run as such.
			Some commands require to be run elevated, when executed against localhost, but not when run against a remote computer.
			This command handles that test and manages the reaction to it.
		
		.PARAMETER ComputerName
			The computer that is being targeted by the calling command.
			This most be a localhost variety, for it to be able to fail.
		
		.PARAMETER Continue
			When using the native capability to terminate on fail, this will call continue in non-silent mode.
		
		.PARAMETER ContinueLabel
			When using the native capability to terminate on fail, and using a continue mode, the continue will continue with this label.
		
		.PARAMETER SilentlyContinue
			When using the native capability to terminate on fail, this will call continue in silent mode.
		
		.PARAMETER NoStop
			Does not call stop-function when the test fails, rather only returns $false instead
	
		.PARAMETER Silent
		    Replaces user friendly yellow warnings with bloody red exceptions of doom!
		    Use this if you want the function to throw terminating errors you want to catch.
		
		.EXAMPLE
			$null = Test-ElevationRequirement -ComputerName $instance -Continue
	
			This will test whether the currently processed instance is localhost and the process is running elevated.
			If it should have elevation but is not running with elevation:
			- In silent mode it will termiante with an exception
			- In default mode, it will continue with the next instance
	
		.EXAMPLE
			if (-not ( Test-ElevationRequirement -ComputerName $instance -NoStop)) {
				# Do whatever
			}
	
			This will test whether the currently processed instance is localhost and the process is running elevated.
			If it isn't running elevated but should be, the overall condition will be met and the if-block is executed.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Stop')]
	Param (
		[DbaInstanceParameter]
		$ComputerName,
		
		[Parameter(ParameterSetName = 'Stop')]
		[switch]
		$Continue,
		
		[Parameter(ParameterSetName = 'Stop')]
		[string]
		$ContinueLabel,
		
		[Parameter(ParameterSetName = 'Stop')]
		[switch]
		$SilentlyContinue,
		
		[Parameter(ParameterSetName = 'NoStop')]
		[switch]
		$NoStop,
		
		[bool]
		$Silent = $Silent
	)
	
	$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	$testResult = $true
	if ($ComputerName.IsLocalHost -and (-not $isElevated)) { $testResult = $false }
	
	switch ($PSCmdlet.ParameterSetName) {
		"NoStop" {
			return $testResult
		}
		"Stop" {
			if ($testResult) { return $testResult }
			
			$splatStopFunction = @{
				Message = "Console not elevated, but elevation is required to perform all actions within this command"
			}
			
			if (Test-Bound "Continue") { $splatStopFunction["Continue"] = $Continue }
			if (Test-Bound "ContinueLabel") { $splatStopFunction["ContinueLabel"] = $ContinueLabel }
			if (Test-Bound "SilentlyContinue") { $splatStopFunction["SilentlyContinue"] = $SilentlyContinue }
			
			. Stop-Function @splatStopFunction -FunctionName (Get-PSCallStack)[1].Command
			return $testResult
		}
	}
}