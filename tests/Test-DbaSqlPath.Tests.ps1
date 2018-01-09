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
        [object[]]$params = (Get-ChildItem function:\Test-DbaSqlPath).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $trueTest = (Get-DbaDatabaseFile -SqlInstance $script:instance2 -Database master)[0].PhysicalName
        if ($trueTest.Length -eq 0) {
            It "has failed setup" {
                Set-TestInconclusive -message "Setup failed"
            }
        }
        $falseTest = 'B:\FloppyDiskAreAwesome'
    }
    Context "Command actually works" {
        $result = Test-DbaSqlPath -SqlInstance $script:instance2 -Path $trueTest
        It "Should only return true if the path IS accessible to the instance" {
            $result | Should Be $true
        }

        $result = Test-DbaSqlPath -SqlInstance $script:instance2 -Path $falseTest
        It "Should only return false if the path IS NOT accessible to the instance" {
            $result | Should Be $false
        }
    }
}
