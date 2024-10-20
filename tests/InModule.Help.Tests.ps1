param($ModuleName = 'dbatools')

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

# Quit failing AppVeyor
if ($env:appveyor) {
    $names = @(
        'Microsoft.SqlServer.Management.XEvent',
        'Microsoft.SqlServer.Management.XEventDbScoped',
        'Microsoft.SqlServer.Management.XEventDbScopedEnum',
        'Microsoft.SqlServer.Management.XEventEnum',
        'Microsoft.SqlServer.Replication',
        'Microsoft.SqlServer.Rmo'
    )

    foreach ($name in $names) {
        $library = Split-Path -Path (Get-Module dbatools*library).Path
        $path = Join-DbaPath -Path $library -ChildPath 'desktop'
        $path = Join-DbaPath -Path $path -ChildPath 'lib'
        Add-Type -Path (Join-Path -Path $path -ChildPath "$name.dll") -ErrorAction SilentlyContinue
    }
}

if ($SkipHelpTest) { return }

. "$PSScriptRoot\InModule.Help.Exceptions.ps1"

BeforeDiscovery {
    # Build the list of commands to test
    $includedNames = (Get-ChildItem "$PSScriptRoot\..\public" | Where-Object Name -like "*.ps1").BaseName
    $commands = Get-Command -Module (Get-Module dbatools) -CommandType Cmdlet, Function, Workflow | Where-Object Name -in $includedNames
}

Describe "Help Tests" {
    Context "Testing help for commands" -ForEach $commands {
        $command = $_
        $commandName = $command.Name

        # Skip all functions that are on the exclusions list
        if ($global:FunctionHelpTestExceptions -contains $commandName) { return }

        # The module-qualified command fails on Microsoft.PowerShell.Archive cmdlets
        BeforeAll {
            $Help = Get-Help $commandName -ErrorAction SilentlyContinue
        }

        Context "Test help for $commandName" {
            It "should not be auto-generated" {
                $Help.Synopsis | Should -Not -BeLike '*`[`<CommonParameters`>`]*' -Because "Auto-generated help indicates missing help content"
            }

            It "gets description for $commandName" {
                $Help.Description | Should -Not -BeNullOrEmpty -Because "Each command should have a description"
            }

            It "gets example code from $commandName" {
                ($Help.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty -Because "Each command should have at least one example code"
            }

            It "gets example help from $commandName" {
                ($Help.Examples.Example.Remarks | Select-Object -First 1).Text | Should -Not -BeNullOrEmpty -Because "Each command should have at least one example description"
            }

            It "There should be a navigation link for $commandName" {
                $Help.RelatedLinks.NavigationLink | Should -Not -BeNullOrEmpty -Because "We need a .LINK for Get-Help -Online to work"
            }

            It "The link for $commandName should be https://dbatools.io/$commandName" {
                $Help.RelatedLinks.NavigationLink.uri | Should -MatchExactly "https://dbatools.io/$commandName" -Because "The web page should be the one for the command"
            }
        }

        Context "Test parameter help for $commandName" {
            BeforeAll {
                $Common = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable',
                'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable'

                $parameters = $command.ParameterSets.Parameters | Sort-Object -Property Name -Unique | Where-Object Name -notin $Common
                $parameterNames = $parameters.Name
                $HelpParameterNames = $Help.Parameters.Parameter.Name | Sort-Object -Unique
            }

            foreach ($parameter in $parameters) {
                $parameterName = $parameter.Name
                $parameterHelp = $Help.Parameters.Parameter | Where-Object Name -EQ $parameterName

                It "gets help for parameter: $parameterName in $commandName" {
                    $parameterHelp.Description.Text | Should -Not -BeNullOrEmpty -Because "Each parameter should have a description"
                }

                It "help for $parameterName parameter in $commandName has correct Mandatory value" {
                    $codeMandatory = $parameter.IsMandatory.ToString()
                    $parameterHelp.Required | Should -Be $codeMandatory -Because "Required value in Help should match IsMandatory property of parameter"
                }

                if ($HelpTestSkipParameterType[$commandName] -contains $parameterName) { continue }

                It "help for $commandName has correct parameter type for $parameterName" {
                    $codeType = $parameter.ParameterType.Name
                    if ($parameter.ParameterType.IsEnum) {
                        # Enumerations often have issues with the typename not being reliably available
                        $names = $parameter.ParameterType.GetEnumNames()
                        $parameterHelp.parameterValueGroup.parameterValue | Should -Be $names -Because "Parameter type in Help should match code"
                    } elseif ($parameter.ParameterType.FullName -in $HelpTestEnumeratedArrays) {
                        # Enumerations often have issues with the typename not being reliably available
                        $names = [Enum]::GetNames($parameter.ParameterType.DeclaredMembers[0].ReturnType)
                        $parameterHelp.parameterValueGroup.parameterValue | Should -Be $names -Because "Parameter type in Help should match code"
                    } else {
                        # To avoid calling Trim method on a null object.
                        $helpType = if ($parameterHelp.parameterValue) { $parameterHelp.parameterValue.Trim() }
                        $helpType | Should -Be $codeType -Because "Parameter type in Help should match code"
                    }
                }
            }

            foreach ($helpParm in $HelpParameterNames) {
                It "finds help parameter in code: $helpParm" {
                    $helpParm -in $parameterNames | Should -Be $true -Because "Help should not have extra parameters not in code"
                }
            }
        }
    }
}
