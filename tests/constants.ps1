# constants
if (Test-Path C:\temp\constants.ps1) {
	. C:\temp\constants.ps1
}
else {
	$script:sql2008 = "localhost\sql2008r2sp2"
	$script:sql2016 = "localhost\sql2016"
	$Instances = @($script:sql2008, $script:sql2016)
}
