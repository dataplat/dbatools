<#
    .SYNOPSIS
        Runs dbatools tests.

    .DESCRIPTION
        This file will either run all tests for dbatools or merely run the specified tests.

    .PARAMETER Path
        The Path to the test files to run
#>
[CmdletBinding()]
Param (
    [string[]]
    $Path,
	
	[ValidateSet('None', 'Default', 'Passed', 'Failed', 'Pending', 'Skipped', 'Inconclusive', 'Describe', 'Context', 'Summary', 'Header', 'All', 'Fails')]
	[string]
	$Show = "All",
	
	[switch]
	$TestIntegration,
    
    [switch]
    $SkipHelpTest,
	
	[switch]
	$IncludeCoverage
)
# required to calculate coverage
$global:dbatools_dotsourcemodule = $true

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$ModuleBase = Split-Path -Path $PSScriptRoot -Parent
if (Get-Module dbatools) { Remove-Module dbatools }

Write-Host "Importing: $ModuleBase\dbatools.psm1"
Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking
$ScriptAnalyzerRules = Get-ScriptAnalyzerRule

. $PSScriptRoot\..\internal\Write-Message.ps1
. $PSScriptRoot\..\internal\Stop-Function.ps1

$testInt = $false
if ($config_TestIntegration) { $testInt = $true }
if ($TestIntegration) { $testInt = $true }

function get-coverageindications($path) {
	$CBHRex = [regex]'(?smi)<#(.*)#>'
	$everything = (Get-Module dbatools).ExportedCommands.Values
	$everyfunction = $everything.Name
	$funcs = @()
	# assuming Get-DbaFoo.Tests.ps1 wants to initiate coverage for "Get-DbaFoo"
	$leaf = split-path $path -Leaf
	$func_name += $leaf.Replace('.Tests.ps1', '')
	if ($func_name -in $everyfunction) {
		$funcs += $func_name
		$f = $everything | where-object Name -eq $func_name
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
		if ($f -in ('Connect-SqlInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
		# can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
		$res = $allfiles | where-object { $_.Name.Replace('.ps1', '') -eq $f }
		if ($res.count -gt 0) {
			$testpaths += $res.FullName
		}
	}
	return $testpaths
}
$counter = 0
if ($Path) {
	foreach ($item in $Path) {
		$counter += 1
		if ($IncludeCoverage) {
			$allpaths = get-coverageindications $Item
		}
		if ($testInt) {
			if ($IncludeCoverage -and $allpaths) {
				Invoke-Pester -Script $item -CodeCoverage $allpaths -Show $Show -PassThru -CodeCoverageOutputFile "$ModuleBase\PesterCoverage$Counter.xml" | Export-CliXml -Path "$ModuleBase\PesterResults$Counter.xml"
			} else {
				Invoke-Pester $item -Show $Show
			}
		} else {
			if ($IncludeCoverage -and $allpaths) {
				Invoke-Pester $item -ExcludeTag "IntegrationTests" -CodeCoverage $allpaths -Show $Show
			} else {
				Invoke-Pester $item -ExcludeTag "IntegrationTests" -Show $Show
			}
		}
	}
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
	
	#handle coverage https://docs.codecov.io/reference#upload
	$report = @{'coverage'=@{}}
	$missed = $results.CodeCoverage | Select-Object -ExpandProperty MissedCommands | Sort-Object -Property File,Line -Unique
	$hits = $results.CodeCoverage | Select-Object -ExpandProperty HitCommands | Sort-Object -Property File,Line -Unique
	$LineCount = @{}
	$hits | ForEach-Object {
		$filename = $_.File.Replace("$ModuleBase\", '').Replace('\','/')
		if ($filename -notin $report['coverage'].Keys) {
			$report['coverage'][$filename] = @{}
			$LineCount[$filename] = (Get-Content $_.File | Measure-Object -Line).Lines
		}
		$report['coverage'][$filename][$_.Line] = 1
	}
	
	$missed | ForEach-Object {
		$filename = $_.File.Replace("$ModuleBase\", '').Replace('\','/')
		if ($filename -notin $report['coverage'].Keys) {
			$report['coverage'][$filename] = @{}
			$LineCount[$filename] = (Get-Content $_.File | Measure-Object -Line).Lines
		}
		if ($_.Line -notin $report['coverage'][$filename].Keys) {
			#miss only if not already covered
			$report['coverage'][$filename][$_.Line] = 0
		}
	}
	
	
	$newreport = @{'coverage'=[ordered]@{}}
	foreach($fname in $report['coverage'].Keys) {
		$Linecoverage = [ordered]@{}
		for($i=1; $i -le $LineCount[$fname]; $i++){
			if ($i -in $report['coverage'][$fname].Keys) {
				$Linecoverage["$i"] = $report['coverage'][$fname][$i]
			}
		}
		$newreport['coverage'][$fname] = $Linecoverage
	}
	$newreport | ConvertTo-Json -Depth 4 -Compress | Out-File -FilePath "$ModuleBase\PesterResultsCoverage.json" -Encoding utf8
	$params = @{}
	$params['branch'] = $env:APPVEYOR_REPO_BRANCH
	$params['service'] = "appveyor"
	$params['job'] = $env:APPVEYOR_ACCOUNT_NAME
	if ($params['job']) { $params['job'] += '/' + $env:APPVEYOR_PROJECT_SLUG }
	if ($params['job']) { $params['job'] += '/' + $env:APPVEYOR_BUILD_VERSION }
	$params['build'] = $env:APPVEYOR_JOB_ID
	$params['pr'] = $env:APPVEYOR_PULL_REQUEST_NUMBER
	$params['slug'] = $env:APPVEYOR_REPO_NAME
	$params['commit'] = $env:APPVEYOR_REPO_COMMIT
	Add-Type -AssemblyName System.Web
	$CodeCovParams = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
	$params.GetEnumerator() | Where-Object Value | ForEach-Object { $CodeCovParams.Add($_.Name, $_.Value) }
	$Request  = [System.UriBuilder]('https://codecov.io/upload/v2')
	$Request.Query = $CodeCovParams.ToString()
	write-host "sending all to $($Request.Uri)"
	Invoke-RestMethod -Uri $Request.Uri -Method Post -InFile "$ModuleBase\PesterResultsCoverage.json" -ContentType 'multipart/form-data' -verbose
}

else {
	if ($testInt) { Invoke-Pester -Show $Show }
	else { Invoke-Pester -ExcludeTag "IntegrationTests" -Show $Show }
}
