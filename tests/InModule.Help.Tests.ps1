Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
<#	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2016 v5.2.119
		Created on:   	4/12/2016 1:11 PM
		Created by:   	June Blender
		Organization: 	SAPIEN Technologies, Inc
		Filename:		*.Help.Tests.ps1
		===========================================================================
	.DESCRIPTION
	To test help for the commands in a module, place this file in the module folder.
	To test any module from any path, use https://github.com/juneb/PesterTDD/Module.Help.Tests.ps1
#>
if ($SkipHelpTest) { return }
. "$ModuleBase\tests\InModule.Help.Exceptions.ps1"

$excludedNames = (Get-ChildItem "$ModuleBase\internal" | Where-Object Name -like "*.ps1" ).BaseName
$commands = Get-Command -Module (Get-Module dbatools) -CommandType Cmdlet, Function, Workflow | Where-Object Name -notin $excludedNames


## When testing help, remember that help is cached at the beginning of each session.
## To test, restart session.

foreach ($command in $commands) {
    $commandName = $command.Name
    
    # Skip all functions that are on the exclusions list
    if ($global:FunctionHelpTestExceptions -contains $commandName) { continue }
    
    # The module-qualified command fails on Microsoft.PowerShell.Archive cmdlets
    $Help = Get-Help $commandName -ErrorAction SilentlyContinue
    
    Describe "Test help for $commandName" {
        
        # If help is not found, synopsis in auto-generated help is the syntax diagram
        It "should not be auto-generated" {
            $Help.Synopsis | Should Not BeLike '*`[`<CommonParameters`>`]*'
        }
        
        # Should be a description for every function
        It "gets description for $commandName" {
            $Help.Description | Should Not BeNullOrEmpty
        }
        
        # Should be at least one example
        It "gets example code from $commandName" {
            ($Help.Examples.Example | Select-Object -First 1).Code | Should Not BeNullOrEmpty
        }
        
        # Should be at least one example description
        It "gets example help from $commandName" {
            ($Help.Examples.Example.Remarks | Select-Object -First 1).Text | Should Not BeNullOrEmpty
        }
        
        Context "Test parameter help for $commandName" {
            
            $Common = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable',
            'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable'
            
            $parameters = $command.ParameterSets.Parameters | Sort-Object -Property Name -Unique | Where-Object Name -notin $common
            $parameterNames = $parameters.Name
            $HelpParameterNames = $Help.Parameters.Parameter.Name | Sort-Object -Unique
            
            foreach ($parameter in $parameters) {
                $parameterName = $parameter.Name
                $parameterHelp = $Help.parameters.parameter | Where-Object Name -EQ $parameterName
                
                # Should be a description for every parameter
                It "gets help for parameter: $parameterName : in $commandName" {
                    $parameterHelp.Description.Text | Should Not BeNullOrEmpty
                }
                
                # Required value in Help should match IsMandatory property of parameter
                It "help for $parameterName parameter in $commandName has correct Mandatory value" {
                    $codeMandatory = $parameter.IsMandatory.toString()
                    $parameterHelp.Required | Should Be $codeMandatory
                }
				
				if ($HelpTestSkipParameterType[$commandName] -contains $parameterName) { continue }
                
                # Parameter type in Help should match code
                It "help for $commandName has correct parameter type for $parameterName" {
                    $codeType = $parameter.ParameterType.Name
                    
					if ($parameter.ParameterType.IsEnum) {
                        # Enumerations often have issues with the typename not being reliably available
                        $names = $parameter.ParameterType::GetNames($parameter.ParameterType)
                        $parameterHelp.parameterValueGroup.parameterValue | Should be $names
                    }
					elseif ($parameter.ParameterType.FullName -in $HelpTestEnumeratedArrays) {
						# Enumerations often have issues with the typename not being reliably available
                        $names = [Enum]::GetNames($parameter.ParameterType.DeclaredMembers[0].ReturnType)
                        $parameterHelp.parameterValueGroup.parameterValue | Should be $names
					}
                    else {
                        # To avoid calling Trim method on a null object.
                        $helpType = if ($parameterHelp.parameterValue) { $parameterHelp.parameterValue.Trim() }
                        $helpType | Should be $codeType 
                    }
                }
            }
            
            foreach ($helpParm in $HelpParameterNames) {
                # Shouldn't find extra parameters in help.
                It "finds help parameter in code: $helpParm" {
                    $helpParm -in $parameterNames | Should Be $true
                }
            }
        }
    }
}
