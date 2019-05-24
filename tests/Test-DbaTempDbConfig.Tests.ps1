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
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Command actually works on $script:instance2" {
        $results = Test-DbaTempdbConfig -SqlInstance $script:instance2
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