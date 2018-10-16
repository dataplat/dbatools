$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 13
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Invoke-SqlCmd2).Parameters.Keys
        $knownParameters = 'ServerInstance','Database','Query','InputFile','Credential','Encrypt','QueryTimeout','ConnectionTimeout','As','SqlParameters','AppendServerInstance','ParseGO','SQLConnection'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database tempdb -Query "Select 'hello' as TestColumn"
    It "returns a datatable" {
        $results.GetType().Name -eq "DataRow" | Should Be $true
    }

    It "returns the proper result" {
        $results.TestColumn -eq 'hello' | Should Be $true
    }

    $results = Invoke-SqlCmd2 -SqlInstance $script:instance1 -Database tempdb -Query "Select 'hello' as TestColumn"
    It "supports SQL instance param" {
        $results.TestColumn -eq 'hello' | Should Be $true
    }
}