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
        [object[]]$params = (Get-ChildItem Function:\Test-DbaSqlManagementObject).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'VersionNumber', 'EnableException'
        it "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $versionMajor = (Connect-DbaInstance -SqlInstance $script:instance2).VersionMajor
    }
    Context "Command actually works" {
        $trueResults = Test-DbaSqlManagementObject -ComputerName $script:instance2 -VersionNumber $versionMajor
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,Version,Exists'.Split(',')
            ($trueResults[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults.Exists | Should Be $true
        }

        $falseResults = Test-DbaSqlManagementObject -ComputerName $script:instance2 -VersionNumber -1
        It "Should return false for VersionNumber -1" {
            $falseResults.Exists | Should Be $false
        }
    }
}
