Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
<#
    .NOTES
        ===========================================================================
        Created with:    SAPIEN Technologies, Inc., PowerShell Studio 2016 v5.2.119
        Created on:      4/12/2016 1:11 PM
        Created by:      June Blender
        Organization:    SAPIEN Technologies, Inc
        Filename:        *.Help.Tests.ps1
        ===========================================================================
    .DESCRIPTION
    To test help for the commands in a module, place this file in the module folder.
    To test any module from any path, use https://github.com/juneb/PesterTDD/Module.Help.Tests.ps1
#>
# quit failing appveyor
if ($env:appveyor) {
    $names = @(
        'Microsoft.SqlServer.XEvent.Linq',
        'Microsoft.SqlServer.Management.XEvent',
        'Microsoft.SqlServer.Management.XEventDbScoped',
        'Microsoft.SqlServer.Management.XEventDbScopedEnum',
        'Microsoft.SqlServer.Management.XEventEnum',
        'Microsoft.SqlServer.Replication',
        'Microsoft.SqlServer.Rmo'
    )

    foreach ($name in $names) {
        Add-Type -Path "C:\github\dbatools\bin\smo\$name.dll" -ErrorAction SilentlyContinue
    }
}

if ($SkipHelpTest) { return }
. "$PSScriptRoot\InModule.Help.Exceptions.ps1"

$includedNames = (Get-ChildItem "$PSScriptRoot\..\functions" | Where-Object Name -like "*.ps1" ).BaseName
$commands = Get-Command -Module (Get-Module dbatools) -CommandType Cmdlet, Function, Workflow | Where-Object Name -in $includedNames

## When testing help, remember that help is cached at the beginning of each session.
## To test, restart session.


foreach ($command in $commands) {
    $commandName = $command.Name

    # Skip all functions that are on the exclusions list
    if ($global:FunctionHelpTestExceptions -contains $commandName) { continue }

    # The module-qualified command fails on Microsoft.PowerShell.Archive cmdlets
    $Help = Get-Help $commandName -ErrorAction SilentlyContinue
    $testhelperrors = 0
    $testhelpall = 0
    Describe "Test help for $commandName" {

        $testhelpall += 1
        if ($Help.Synopsis -like '*`[`<CommonParameters`>`]*') {
            # If help is not found, synopsis in auto-generated help is the syntax diagram
            It "should not be auto-generated" {
                $Help.Synopsis | Should Not BeLike '*`[`<CommonParameters`>`]*'
            }
            $testhelperrors += 1
        }

        $testhelpall += 1
        if ([String]::IsNullOrEmpty($Help.Description.Text)) {
            # Should be a description for every function
            It "gets description for $commandName" {
                $Help.Description | Should Not BeNullOrEmpty
            }
            $testhelperrors += 1
        }

        $testhelpall += 1
        if ([String]::IsNullOrEmpty(($Help.Examples.Example | Select-Object -First 1).Code)) {
            # Should be at least one example
            It "gets example code from $commandName" {
                ($Help.Examples.Example | Select-Object -First 1).Code | Should Not BeNullOrEmpty
            }
            $testhelperrors += 1
        }

        $testhelpall += 1
        if ([String]::IsNullOrEmpty(($Help.Examples.Example.Remarks | Select-Object -First 1).Text)) {
            # Should be at least one example description
            It "gets example help from $commandName" {
                ($Help.Examples.Example.Remarks | Select-Object -First 1).Text | Should Not BeNullOrEmpty
            }
            $testhelperrors += 1
        }
        # :-(
        $testhelpall += 1
        if ([string]::IsNullOrEmpty($help.relatedLinks.NavigationLink)) {
            # Should have a navigation link
            It "There should be a navigation link for $commandName" {
                $help.relatedLinks.NavigationLink | Should -Not -BeNullOrEmpty -Because "We need a .LINK for Get-Help -Online to work"
            }
            $testhelperrors += 1
        }
        # :-(
        $testhelpall += 1
        if (-not ([string]::Equals($help.relatedLinks.NavigationLink.uri, "https://dbatools.io/$commandName"))) {
            # the link should point to the correct page
            It "The link for $commandName should be https://dbatools.io/$commandName" {
                $help.relatedLinks[0].NavigationLink.uri | Should -MatchExactly "https://dbatools.io/$commandName"  -Because "The web-page should be the one for the command!"
            }
            $testhelperrors += 1
        }

        if ($testhelperrors -eq 0) {
            It "Ran silently $testhelpall tests" {
                $testhelperrors | Should be 0
            }
        }

        $testparamsall = 0
        $testparamserrors = 0
        Context "Test parameter help for $commandName" {

            $Common = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable',
            'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable'

            $parameters = $command.ParameterSets.Parameters | Sort-Object -Property Name -Unique | Where-Object Name -notin $common
            $parameterNames = $parameters.Name
            $HelpParameterNames = $Help.Parameters.Parameter.Name | Sort-Object -Unique
            foreach ($parameter in $parameters) {
                $parameterName = $parameter.Name
                $parameterHelp = $Help.parameters.parameter | Where-Object Name -EQ $parameterName

                $testparamsall += 1
                if ([String]::IsNullOrEmpty($parameterHelp.Description.Text)) {
                    # Should be a description for every parameter
                    It "gets help for parameter: $parameterName : in $commandName" {
                        $parameterHelp.Description.Text | Should Not BeNullOrEmpty
                    }
                    $testparamserrors += 1
                }

                $testparamsall += 1
                $codeMandatory = $parameter.IsMandatory.toString()
                if ($parameterHelp.Required -ne $codeMandatory) {
                    # Required value in Help should match IsMandatory property of parameter
                    It "help for $parameterName parameter in $commandName has correct Mandatory value" {
                        $parameterHelp.Required | Should Be $codeMandatory
                    }
                    $testparamserrors += 1
                }

                if ($HelpTestSkipParameterType[$commandName] -contains $parameterName) { continue }

                $codeType = $parameter.ParameterType.Name

                $testparamsall += 1
                if ($parameter.ParameterType.IsEnum) {
                    # Enumerations often have issues with the typename not being reliably available
                    $names = $parameter.ParameterType::GetNames($parameter.ParameterType)
                    if ($parameterHelp.parameterValueGroup.parameterValue -ne $names) {
                        # Parameter type in Help should match code
                        It "help for $commandName has correct parameter type for $parameterName" {
                            $parameterHelp.parameterValueGroup.parameterValue | Should be $names
                        }
                        $testparamserrors += 1
                    }
                } elseif ($parameter.ParameterType.FullName -in $HelpTestEnumeratedArrays) {
                    # Enumerations often have issues with the typename not being reliably available
                    $names = [Enum]::GetNames($parameter.ParameterType.DeclaredMembers[0].ReturnType)
                    if ($parameterHelp.parameterValueGroup.parameterValue -ne $names) {
                        # Parameter type in Help should match code
                        It "help for $commandName has correct parameter type for $parameterName" {
                            $parameterHelp.parameterValueGroup.parameterValue | Should be $names
                        }
                        $testparamserrors += 1
                    }
                } else {
                    # To avoid calling Trim method on a null object.
                    $helpType = if ($parameterHelp.parameterValue) { $parameterHelp.parameterValue.Trim() }
                    if ($helpType -ne $codeType ) {
                        # Parameter type in Help should match code
                        It "help for $commandName has correct parameter type for $parameterName" {
                            $helpType | Should be $codeType
                        }
                        $testparamserrors += 1
                    }
                }
            }
            foreach ($helpParm in $HelpParameterNames) {
                $testparamsall += 1
                if ($helpParm -notin $parameterNames) {
                    # Shouldn't find extra parameters in help.
                    It "finds help parameter in code: $helpParm" {
                        $helpParm -in $parameterNames | Should Be $true
                    }
                    $testparamserrors += 1
                }
            }
            if ($testparamserrors -eq 0) {
                It "Ran silently $testparamsall tests" {
                    $testparamserrors | Should be 0
                }
            }
        }
    }
}