$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaServerName).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Detailed', 'ExcludeSsrs', 'EnableException'
        it "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command tests servername" {
        $results = Test-DbaServerName -SqlInstance $script:instance2
        It "should say rename is not required" {
            $results.RenameRequired | Should -Be $false
        }
        
        It "returns the correct properties" {
            $ExpectedProps = 'ComputerName,ServerName,RenameRequired,Updatable,Warnings,Blockers,SqlInstance,InstanceName'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}