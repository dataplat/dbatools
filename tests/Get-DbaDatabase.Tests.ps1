#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if (-not $PSScriptRoot) {
	$PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{ }
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
	$Verbose.add("Verbose", $True)
}

$scriptname = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
$Name = $scriptname.Split('.')[0]

Describe 'Script Analyzer Tests' -Tags @('ScriptAnalyzer') {
	Context "Testing $Name for Standard Processing" {
		foreach ($rule in $ScriptAnalyzerRules) {
			$i = $ScriptAnalyzerRules.IndexOf($rule)
			It "passes the PSScriptAnalyzer Rule number $i - $rule  " {
				(Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\internal\$scriptname" -IncludeRule $rule.RuleName).Count | Should Be 0
			}
		}
	}
}

# Test functionality

Describe "Get-DbaDatabase Integration Tests" -Tags "Integrationtests" {

    Context "Count system databases on localhost" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoUserDb 
        It "Should report the right number of databases" {
            $results.Count | Should Be 4
        }
    }

    Context "Check that master database is in FULL recovery mode" {
            $results = Get-DbaDatabase -SqlInstance localhost -Database master
            It "Should say the recovery mode of master is Full" {
                $results.RecoveryModel | Should Be "Full"
            }
        }
}