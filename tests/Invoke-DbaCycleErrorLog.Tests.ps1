$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Invoke-DbaCycleErrorLog).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Type', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Test" -Tag "IntegrationTests" {
    $results = Invoke-DbaCycleErrorLog -SqlInstance $script:instance1 -Type instance

    Context "Validate output" {
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,LogType,IsSuccessful,Notes'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Should cycle instance error log" {
            $results.LogType | Should Be "instance"
        }
    }
}
