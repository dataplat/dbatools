#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools"
)

# quit failing appveyor
if ($env:appveyor) {
    $names = @(
        "Microsoft.SqlServer.Management.XEvent",
        "Microsoft.SqlServer.Management.XEventDbScoped",
        "Microsoft.SqlServer.Management.XEventDbScopedEnum",
        "Microsoft.SqlServer.Management.XEventEnum",
        "Microsoft.SqlServer.Replication",
        "Microsoft.SqlServer.Rmo"
    )

    foreach ($name in $names) {
        $library = Split-Path -Path (Get-Module dbatools*library).Path
        $path = Join-DbaPath -Path $library -ChildPath desktop
        $path = Join-DbaPath -Path $path -ChildPath lib
        Add-Type -Path (Join-Path -path $path -ChildPath "$name.dll")
    }
}

if ($SkipHelpTest) { return }
. "$PSScriptRoot\InModule.Help.Exceptions.ps1"

## When testing help, remember that help is cached at the beginning of each session.
## To test, restart session.

Describe "dbatools Module Help" -Tag "Help" {
    BeforeAll {
        $includedNames = (Get-ChildItem "$PSScriptRoot\..\public" | Where-Object Name -like "*.ps1").BaseName
        $global:commandsWithHelp = Get-Command -Module (Get-Module dbatools) -CommandType Cmdlet, Function, Workflow | Where-Object Name -in $includedNames
    }

    foreach ($command in $global:commandsWithHelp) {
        $commandName = $command.Name

        # Skip all functions that are on the exclusions list
        if ($global:FunctionHelpTestExceptions -contains $commandName) { continue }

        Describe "Help for $commandName" {
            BeforeAll {
                $Help = Get-Help $commandName -ErrorAction SilentlyContinue
            }

            It "should not be auto-generated" {
                # If help is not found, synopsis in auto-generated help is the syntax diagram
                $Help.Synopsis | Should -Not -BeLike "*`[`<CommonParameters`>`]*"
            }

            It "should have a description" {
                # Should be a description for every function
                $Help.Description.Text | Should -Not -BeNullOrEmpty
            }

            It "should have at least one example with code" {
                ($Help.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty
            }

            It "should have at least one example with remarks" {
                # Should be at least one example description
                ($Help.Examples.Example.Remarks | Select-Object -First 1).Text | Should -Not -BeNullOrEmpty
            }
            # :-)
            It "should have a related navigation link" {
                # Should have a navigation link
                $help.relatedLinks.NavigationLink | Should -Not -BeNullOrEmpty -Because "We need a .LINK for Get-Help -Online to work"
            }
            # :-)
            It "should have the correct online link" {
                # the link should point to the correct page
                $help.relatedLinks.NavigationLink[0].uri | Should -Be "https://dbatools.io/$commandName" -Because "The web-page should be the one for the command!"
            }

            Context "Parameter help" {
                BeforeAll {
                    $Common = "Debug", "ErrorAction", "ErrorVariable", "InformationAction", "InformationVariable", "OutBuffer", "OutVariable", "PipelineVariable", "Verbose", "WarningAction", "WarningVariable"
                    $commandParameters = $command.ParameterSets.Parameters | Sort-Object -Property Name -Unique | Where-Object Name -notin $common
                    $HelpParameterNames = $Help.Parameters.Parameter.Name | Sort-Object -Unique
                }

                It "should not have extra parameters in help" {
                    $extraParams = $HelpParameterNames | Where-Object { $PSItem -notin $commandParameters.Name }
                    $extraParams | Should -BeNullOrEmpty
                }

                foreach ($parameter in $commandParameters) {
                    Context "for parameter '$($parameter.Name)'" {
                        BeforeAll {
                            $parameterName = $parameter.Name
                            $parameterHelp = $Help.parameters.parameter | Where-Object Name -EQ $parameterName
                        }

                        It "should have a description" {
                            # Should be a description for every parameter
                            $parameterHelp.Description.Text | Should -Not -BeNullOrEmpty
                        }

                        It "should have the correct 'Required' value" {
                            # Required value in Help should match IsMandatory property of parameter
                            $codeMandatory = $parameter.IsMandatory.ToString()
                            $parameterHelp.Required | Should -Be $codeMandatory
                        }

                        if ($HelpTestSkipParameterType[$commandName] -notcontains $parameter.Name) {
                            It "should have the correct parameter type" {
                                # Parameter type in Help should match code
                                $codeType = $parameter.ParameterType.Name
                                if ($parameter.ParameterType.IsEnum) {
                                    # Enumerations often have issues with the typename not being reliably available
                                    $names = $parameter.ParameterType::GetNames($parameter.ParameterType)
                                    Compare-Object -ReferenceObject $names -DifferenceObject $parameterHelp.parameterValueGroup.parameterValue | Should -BeNullOrEmpty
                                }
                                elseif ($parameter.ParameterType.FullName -in $HelpTestEnumeratedArrays) {
                                    # Enumerations often have issues with the typename not being reliably available
                                    $names = [Enum]::GetNames($parameter.ParameterType.DeclaredMembers[0].ReturnType)
                                    Compare-Object -ReferenceObject $names -DifferenceObject $parameterHelp.parameterValueGroup.parameterValue | Should -BeNullOrEmpty
                                }
                                else {
                                    # To avoid calling Trim method on a null object.
                                    $helpType = if ($parameterHelp.parameterValue) { $parameterHelp.parameterValue.Trim() }
                                    $helpType | Should -Be $codeType
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
