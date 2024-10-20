param($ModuleName = 'dbatools')

Describe "Enable-DbaFilestream" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaFilestream
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "FileStreamLevel",
            "ShareName",
            "Force",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Enable-DbaFilestream Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
    }

    BeforeAll {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
    }

    AfterAll {
        if ($OriginalFileStream.InstanceAccessLevel -eq 0) {
            Disable-DbaFilestream -SqlInstance $global:instance1 -Confirm:$false
        } else {
            Enable-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $OriginalFileStream.InstanceAccessLevel -Confirm:$false
        }
    }

    Context "Changing FileStream Level" {
        BeforeAll {
            $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Enable-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $NewLevel -Confirm:$false
        }

        It "Should have changed the FileStream Level" {
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}
