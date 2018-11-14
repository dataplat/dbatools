$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.

            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
               #>
        $paramCount = 7
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Enable-DbaFilestream).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'FileStreamLevel', 'ShareName', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

<#
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $script:instance1
    }
    AfterAll {
        if ($OriginalFileStream.InstanceAccessLevel -eq 0) {
            Disable-DbaFilestream -SqlInstance $script:instance1 -Confirm:$false
        } else {
            Enable-DbaFilestream -SqlInstance $script:instance1 -FileStreamLevel $OriginalFileStream.InstanceAccessLevel -Confirm:$false
        }
    }

    Context "Changing FileStream Level" {
        $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
        $results = Enable-DbaFilestream -SqlInstance $script:instance1 -FileStreamLevel $NewLevel -Confirm:$false
        It "Should have changed the FileStream Level" {
            $results.InstanceAccessLevel | Should be $NewLevel
        }
    }
}
#>