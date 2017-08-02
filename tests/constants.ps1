# constants
if (Test-Path C:\temp\constants.ps1) {
	. C:\temp\constants.ps1
}
else {
	$script:instance1 = "sql2016a"
	$script:instance2 = "localhost\sql2016"
	$script:appeyorlabrepo = "C:\github\appveyor-lab"
	$instances = @($script:instance1, $script:instance2)
	$ssisserver = "localhost\sql2016"
}