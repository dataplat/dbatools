<# 
.SYNOPSIS 
This script will invoke Pester tests, then serialize XML results and pull them in appveyor.yml

.DESCRIPTION
Internal function that creates SMO server object.

.PARAMETER Finalize
If Finalize is specified, we collect XML output, upload tests, and indicate build errors

.PARAMETER PSVersion
The version of PS

.PARAMETER TestFile
The output file

.PARAMETER ProjectRoot
The appveyor project root 

.PARAMETER ModuleBase
The location of the module

.EXAMPLE
.\appveyor.pester.ps1
Executes the test

.EXAMPLE
.\appveyor.pester.ps1 -Finalize
Finalizes the tests
#>
param (
	[switch]$Finalize,
	$PSVersion = $PSVersionTable.PSVersion.Major,
	$TestFile = "TestResultsPS$PSVersion.xml",
	$ProjectRoot = $ENV:APPVEYOR_BUILD_FOLDER,
	$ModuleBase = $ProjectRoot,
	[switch]$IncludeCoverage
)

# Move to the project root
Set-Location $ModuleBase
# required to calculate coverage
$global:dbatools_dotsourcemodule = $true

Remove-Module dbatools -ErrorAction Ignore
Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking
$ScriptAnalyzerRules = Get-ScriptAnalyzerRule

function Get-CoverageIndications($path) {
	# takes a test file path and figures out what to analyze for coverage (i.e. dependencies)
	$CBHRex = [regex]'(?smi)<#(.*)#>'
	$everything = (Get-Module dbatools).ExportedCommands.Values
	$everyfunction = $everything.Name
	$funcs = @()
	# assuming Get-DbaFoo.Tests.ps1 wants coverage for "Get-DbaFoo"
	$leaf = Split-Path $path -Leaf
	$func_name += $leaf.Replace('.Tests.ps1', '')
	if ($func_name -in $everyfunction) {
		$funcs += $func_name
		$f = $everything | Where-Object Name -eq $func_name
		$source = $f.Definition
		$CBH = $CBHRex.match($source).Value
		$cmdonly = $source.Replace($CBH, '')
		foreach($e in $everyfunction) {
			# hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
			$searchme = "$e "
			if ($cmdonly.contains($searchme)) {
				$funcs += $e
			}
		}
	}
	$testpaths = @()
	$allfiles = Get-ChildItem -File -Path "$ModuleBase\internal", "$ModuleBase\functions" -Filter '*.ps1'
	foreach($f in $funcs) {
		# exclude always used functions ?!
		if ($f -in ('Connect-SqlInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
		# can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
		$res = $allfiles | Where-Object { $_.Name.Replace('.ps1', '') -eq $f }
		if ($res.count -gt 0) {
			$testpaths += $res.FullName
		}
	}
	return @() + ($testpaths | Select-Object -Unique)
}


if (-not $Finalize) {
	# Invoke pester.groups.ps1 to know which tests to run
	. "$ModuleBase\tests\pester.groups.ps1"
	# retrieve all .Tests.
	$AllDbatoolsTests = Get-ChildItem -File -Path $ModuleBase\tests\*.Tests.ps1
	# exclude "disabled"
	$AllTests = $AllDbatoolsTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -notin $TestsRunGroups['disabled'] }
	# only in appveyor, disable uncooperative tests
	$AllTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -notin $TestsRunGroups['appveyor_disabled'] }

	# Inspect special words
	$TestsToRunMessage = "$($env:APPVEYOR_REPO_COMMIT_MESSAGE) $($env:APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED)"
	$TestsToRunRegex = [regex] '(?smi)\(do (?<do>[^)]+)\)'
	$TestsToRunMatch = $TestsToRunRegex.Match($TestsToRunMessage).Groups['do'].Value
	if ($TestsToRunMatch.Length -gt 0) {
		$TestsToRun = "*$TestsToRunMatch*"
		$AllTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -like $TestsToRun }
		Write-Host -ForegroundColor DarkGreen "Commit message: Reduced to $($AllTests.Length) out of $($AllDbatoolsTests.Length) tests"
		if ($AllTests.Length -eq 0) {
			throw "something went wrong, nothing to test"
		}
	} else {
		$TestsToRun = "*.Tests.*"
	}


	# do we have a scenario ?
	if ($env:SCENARIO) {
		# if so, do we have a group with tests to run ?
		if ($env:SCENARIO -in $TestsRunGroups.Keys) {
			$AllScenarioTests = $AllTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -in $TestsRunGroups[$env:SCENARIO] }
		} else {
			$AllScenarioTests = $AllTests
			# we have a scenario, but no specific group. Let's run any other test
			foreach($group in $TestsRunGroups.Keys) {
				$AllScenarioTests = $AllScenarioTests | Where-Object { ($_.Name -replace '\.Tests\.ps1$', '') -notin $TestsRunGroups[$group] }
			}
		}
	} else {
		$AllScenarioTests = $AllTests
	}

	Write-Host -ForegroundColor DarkGreen "Test Groups   : Reduced to $($AllScenarioTests.Length) out of $($AllDbatoolsTests.Length) tests"
	if ($AllTests.Length -eq 0 -and $AllScenarioTests.Length -eq 0) {
		throw "something went wrong, nothing to test"
	}
}

#Run a test with the current version of PowerShell
#Make things faster by removing most output
if (-not $Finalize) {
	Write-Output "Testing with PowerShell $PSVersion"
	Import-Module Pester
	Set-Variable ProgressPreference -Value SilentlyContinue
	# invoking a single invoke-pester consumes too much memory, let's go file by file
	$AllTestsWithinScenario = Get-ChildItem -File -Path $AllScenarioTests
	$counter = 0
	foreach($f in $AllTestsWithinScenario) {
		$counter += 1
		write-host -ForegroundColor yellow "Inspecting $f"
		$CoverFiles = Get-CoverageIndications $f
		write-host -ForegroundColor yellow "figured out coverage: $($CoverFiles -join ',')"
		Invoke-Pester -Script $f.FullName -Show None -PassThru | Export-Clixml -Path "$ModuleBase\PesterResults$PSVersion$counter.xml"
	}
	#Invoke-Pester -Script $AllScenarioTests -Show None -PassThru | Export-Clixml -Path "$ModuleBase\PesterResults$PSVersion.xml"
}
else {
	# Unsure why we're uploading so I removed it for now
	<#
	#If finalize is specified, check for failures and  show status
	$allfiles = Get-ChildItem -Path $ModuleBase\*Results*.xml | Select-Object -ExpandProperty FullName
	Write-Output "Finalizing results and collating the following files:"
	Write-Output ($allfiles | Out-String)
	
	#Upload results for test page
	Get-ChildItem -Path "$ModuleBase\TestResultsPS*.xml" | Foreach-Object {
		
		$Address = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
		$Source = $_.FullName
		
		Write-Output "Uploading files: $Address $Source"
		
		(New-Object System.Net.WebClient).UploadFile($Address, $Source)
		
		Write-Output "You can download it from https://ci.appveyor.com/api/buildjobs/$($env:APPVEYOR_JOB_ID)/tests"
	}
	#>
	#What failed? How many tests did we run ?
	$results = @(Get-ChildItem -Path "$ModuleBase\PesterResults*.xml" | Import-Clixml)
	
	$totalcount = $results | Select-Object -ExpandProperty TotalCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
	$failedcount = $results | Select-Object -ExpandProperty FailedCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
	
	
	if ($failedcount -gt 0) {
		$faileditems = $results | Select-Object -ExpandProperty TestResult | Where-Object { $_.Passed -notlike $True }
		
		if ($faileditems) {
			Write-Warning "Failed tests summary:"
			$faileditems | ForEach-Object {
				$name = $_.Name
				[pscustomobject]@{
					Describe = $_.Describe
					Context = $_.Context
					Name = "It $name"
					Result = $_.Result
					Message = $_.FailureMessage
				}
			} | Sort-Object Describe, Context, Name, Result, Message | Format-List
			
			throw "$failedcount tests failed."
		}
	}
}
