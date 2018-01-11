$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
        $OriginalFileStream = Get-DbaFileStream -SqlInstance $script:instance1
	}
	AfterAll {
        Set-DbaFileStream -SqlInstance $script:instance1 -FileStreamLevel $OriginalFileStream.FileStreamStateId -force
	}

    Context "Testing Connection Properties" {
        Mock Connect-SqlInstance { throw }
        It "Should Throw on a bad instance" {
            {Set-DbaFileStream -Sqlinstance bad -FileStreamLevel 2 -EnableException $true } | Should Throw
        }
    }

    Context "Skipping 'No Change'" {
        $output = Set-DbaFileStream -SqlInstance $script:instance1 -FileStreamLevel $OriginalFileStream.FileStreamStateId -Force -WarningVariable warnvar -WarningAction silentlyContinue -ErrorVariable errvar -Erroraction silentlyContinue
        It "Should Do Nothing"{
            $output.RestartStatus | Should Be 'No restart, as no change in values'
        }
    }

    Context "Changing FileStream Level"{
        $NewLevel = ($OriginalFileStream.FileStreamStateId + 1)%3 #Move it on one, but keep it less than 4 with modulo division 
        $null = Set-DbaFileStream -SqlInstance $script:instance1 -FileStreamLevel $NewLevel -Force -WarningVariable warnvar -WarningAction silentlyContinue -ErrorVariable errvar -Erroraction silentlyContinue
        $output = Get-DbaFileStream -SqlInstance $script:instance1
        It "Should have changed the FileStream Level"{
            $output.FileStreamStateId | Should be $NewLevel
        }
        It "Should have restarted the Instance" {
            $results = Get-DbaUptime -SqlInstance $script:instance1
            ((get-Date) - $results.SqlStartTime).Minutes | Should BeLessThan 3
        }
    }
}