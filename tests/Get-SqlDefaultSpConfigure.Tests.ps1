$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# import internal function
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Get-SqlDefaultSpConfigure.ps1'))

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [array]$knownParameters = 'SqlVersion'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "Try all versions of SQL" {
        $versionName = @{8 = "2000"
            9              = "2005"
            10             = "2008/2008R2"
            11             = "2012"
            12             = "2014"
            13             = "2016"
            14             = "2017"
            15             = "2019"
        }

        foreach ($version in 8..14) {
            $results = Get-SqlDefaultSPConfigure -SqlVersion $version

            It "Should return results for $($versionName.item($version))" {
                $results | Should Not BeNullOrEmpty
            }

            It "Should return 'System.Management.Automation.PSCustomObject' object" {
                $results.GetType().fullname | Should Be "System.Management.Automation.PSCustomObject"
            }
        }
    }
}