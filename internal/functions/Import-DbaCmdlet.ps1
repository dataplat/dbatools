function Import-DbaCmdlet {
    <#
    .SYNOPSIS
        Loads a cmdlet into the current context.

    .DESCRIPTION
        Loads a cmdlet into the current context.
        This can be used to register a cmdlet during module import, making it easy to have hybrid modules publishing both cmdlets and functions.
        Can also be used to register cmdlets written in PowerShell classes.

    .PARAMETER Name
        The name of the cmdlet to register.

    .PARAMETER Type
        The type of the class implementing the cmdlet.

    .PARAMETER HelpFile
        Path to the help XML containing the help for the cmdlet.

    .PARAMETER Module
        Module to inject the cmdlet into.

    .EXAMPLE
        PS C:\> Import-DbaCmdlet -Name Get-Something -Type ([GetSomethingCommand])

        Imports the Get-Something cmdlet into the current context.

    .EXAMPLE
        PS C:\> Import-DbaCmdlet -Name Get-Something -Type ([GetSomethingCommand]) -Module (Get-Module PSReadline)

        Imports the Get-Something cmdlet into the PSReadline module.

    .NOTES
        Original Author: Chris Dent
        Link: https://www.indented.co.uk/cmdlets-without-a-dll/
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]
        $Name,

        [Parameter(Mandatory)]
        [Type]
        $Type,

        [string]
        $HelpFile,

        [System.Management.Automation.PSModuleInfo]
        $Module
    )

    begin {
        $scriptBlock = {
            param (
                [String]
                $Name,

                [Type]
                $Type,

                [string]
                $HelpFile
            )

            $sessionStateCmdletEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry(
                $Name,
                $Type,
                $HelpFile
            )

            # System.Management.Automation.Runspaces.LocalPipeline will let us get at ExecutionContext.
            # Note: $ExecutionContext is *not* an instance of this object.
            $pipelineType = [PowerShell].Assembly.GetType('System.Management.Automation.Runspaces.LocalPipeline')
            $method = $pipelineType.GetMethod(
                'GetExecutionContextFromTLS',
                [System.Reflection.BindingFlags]'Static,NonPublic'
            )

            # Invoke the method to get an instance of ExecutionContext.
            $context = $method.Invoke(
                $null,
                [System.Reflection.BindingFlags]'Static,NonPublic',
                $null,
                $null,
                (Get-Culture)
            )

            # Get the SessionStateInternal type
            $internalType = [PowerShell].Assembly.GetType('System.Management.Automation.SessionStateInternal')

            # Get a valid constructor which accepts a param of type ExecutionContext
            $constructor = $internalType.GetConstructor(
                [System.Reflection.BindingFlags]'Instance,NonPublic',
                $null,
                $context.GetType(),
                $null
            )

            # Get the SessionStateInternal for this execution context
            $sessionStateInternal = $constructor.Invoke($context)

            # Get the method which allows Cmdlets to be added to the session
            $method = $internalType.GetMethod(
                'AddSessionStateEntry',
                [System.Reflection.BindingFlags]'Instance,NonPublic',
                $null,
                $sessionStateCmdletEntry.GetType(),
                $null
            )
            # Invoke the method.
            $method.Invoke($sessionStateInternal, $sessionStateCmdletEntry)
        }
    }

    process {
        if (-not $Module) { $scriptBlock.Invoke($Name, $Type, $HelpFile) }
        else { $Module.Invoke($scriptBlock, @($Name, $Type, $HelpFile)) }
    }
}