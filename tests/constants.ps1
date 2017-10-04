# constants
if (Test-Path C:\temp\constants.ps1) {
	Write-Vervose "C:\temp\constants.ps1 found."
	. C:\temp\constants.ps1
}
elseif (Test-Path "$PSScriptRoot\constants.local.ps1") {
	Write-Verbose "tests\constants.local.ps1 found." 
	. "$PSScriptRoot\constants.local.ps1"
}
else {
	$script:instance1 = "localhost\sql2008r2sp2"
	$script:instance2 = "localhost\sql2016"
	$script:appeyorlabrepo = "C:\github\appveyor-lab"
	$instances = @($script:instance1, $script:instance2)
	$ssisserver = "localhost\sql2016"
}
