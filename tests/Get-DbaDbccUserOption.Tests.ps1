$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Option', 'EnableException'
        $paramCount = $knownParameters.Count
        $SupportShouldProcess = $false
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        it "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
Describe "$commandname  Integration Test" -Tag "IntegrationTests" {
    $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Option', 'Value'
    $result = Get-DbaDbccUserOption -SqlInstance $script:instance2

    Context "Validate standard output" {
        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }

    Context "Command returns proper info" {
        It "returns results for DBCC USEROPTIONS" {
            $result.Count -gt 0 | Should Be $true
        }
    }

    Context "Accepts an Option Value" {
        $result = Get-DbaDbccUserOption -SqlInstance $script:instance2 -Option ansi_nulls
        It "Gets results" {
            $result | Should Not Be $null
        }
        It "Returns only one result" {
            $result.Option -eq 'ansi_nulls' | Should Be $true
        }
    }
}
