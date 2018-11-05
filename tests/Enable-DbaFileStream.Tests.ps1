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
        $OriginalFileStream = Get-DbaFileStream -SqlInstance $script:instance1
    }
    AfterAll {
        Set-DbaFileStream -SqlInstance $script:instance1 -FileStreamLevel $OriginalFileStream.FileStreamStateId -force
    }

    Context "Skipping 'No Change'" {
        $output = Set-DbaFileStream -SqlInstance $script:instance1 -FileStreamLevel $OriginalFileStream.FileStreamStateId -Force -WarningVariable warnvar -WarningAction silentlyContinue -ErrorVariable errvar -Erroraction silentlyContinue
        It "Should Do Nothing" {
            $output.RestartStatus | Should Be 'No restart, as no change in values'
        }
    }

    Context "Changing FileStream Level" {
        $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
        $null = Set-DbaFileStream -SqlInstance $script:instance1 -FileStreamLevel $NewLevel -Force -WarningVariable warnvar -WarningAction silentlyContinue -ErrorVariable errvar -Erroraction silentlyContinue
        $output = Get-DbaFileStream -SqlInstance $script:instance1
        It "Should have changed the FileStream Level" {
            $output.FileStreamStateId | Should be $NewLevel
        }
        It "Should have restarted the Instance" {
            $results = Get-DbaUptime -SqlInstance $script:instance1
            ((get-Date) - $results.SqlStartTime).Minutes | Should BeLessThan 3
        }
    }
}
#>