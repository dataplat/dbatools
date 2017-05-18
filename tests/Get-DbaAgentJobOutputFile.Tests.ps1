#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{ }
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
    $Verbose.add("Verbose", $True)
}

$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
$Name = $sut.Split('.')[0]

Describe 'Script Analyzer Tests' -Tag @('ScriptAnalyzer') {
    Context "Testing $Name for Standard Processing" {
        foreach ($rule in $ScriptAnalyzerRules) {
            $i = $ScriptAnalyzerRules.IndexOf($rule)
            It "passes the PSScriptAnalyzer Rule number $i - $rule  " {
                (Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\functions\$sut" -IncludeRule $rule.RuleName).Count | Should Be 0
            }
        }
    }
}

## needs some proper tests for the function here
Describe "$Name Tests" -Tag @('Command') {
    Context "Input Validation" {
        It 'SqlServer parameter is empty' {
            { Get-DbaJobOutputFile -SqlServer '' -WarningAction Stop 3> $null } | Should Throw
        }
        It 'SqlServer parameter host cannot be found' {
            Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
            { Get-DbaJobOutputFile -SqlServer 'ABC' -WarningAction Stop 3> $null } | Should Throw
        }
    } ## End Context Input
}

    