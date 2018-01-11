<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.

            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
        #>
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaTempDbConfiguration).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Detailed'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Test-DbaTempDbConfiguration -SqlInstance $script:instance2
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Rule,Recommended,CurrentSetting,IsBestPractice,Notes'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        $rule = 'File Location'
        It "Should return false for IsBestPractice with rule: $rule" {
            ($results | Where-Object Rule -match $rule).IsBestPractice | Should Be $false
        }
        It "Should return false for Recommended with rule: $rule" {
            ($results | Where-Object Rule -match $rule).Recommended | Should Be $false
        }
        $rule = 'TF 1118 Enabled'
        It "Should return true for IsBestPractice with rule: $rule" {
            ($results | Where-Object Rule -match $rule).Recommended | Should Be $true
        }
    }
}