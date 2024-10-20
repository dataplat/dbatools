param($ModuleName = 'dbatools')

Describe "Copy-DbaXESessionTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaXESessionTemplate
        }

        $params = @(
            "Path",
            "Destination",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')

            # Ensure the destination directory exists
            $destinationPath = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates"
            if (-not (Test-Path $destinationPath)) {
                New-Item -Path $destinationPath -ItemType Directory -Force
            }

            # Copy the templates
            $null = Copy-DbaXESessionTemplate -Destination $destinationPath
        }

        It "Copies the files properly" {
            $source = (Get-DbaXESessionTemplate | Where-Object Source -ne Microsoft | Select-Object -First 1).Name
            $result = Get-ChildItem $destinationPath | Where-Object Name -eq $source
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
