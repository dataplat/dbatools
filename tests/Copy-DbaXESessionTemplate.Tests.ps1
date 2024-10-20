param($ModuleName = 'dbatools')

Describe "Copy-DbaXESessionTemplate" -Tag 'UnitTests' {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaXESessionTemplate
        }
        $parms = @(
            'Path',
            'Destination',
            'EnableException'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Copy-DbaXESessionTemplate Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = Copy-DbaXESessionTemplate *>1
        $global:source = ((Get-DbaXESessionTemplate -Path $Path | Where-Object Source -ne Microsoft).Path | Select-Object -First 1).Name
    }

    Context "Get Template Index" {
        It "copies the files properly" {
            Get-ChildItem "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" | Where-Object Name -eq $global:source | Should -Not -BeNull
        }
    }
}
