function Register-DbatoolsConfigValidation {
    <#
        .SYNOPSIS
            Registers a validation scriptblock for use with the configuration system.

        .DESCRIPTION
            Registers a validation scriptblock for use with the configuration system.

            The scriptblock must be designed according to a few guidelines:
            - It must not throw exceptions
            - It must accept a single parameter (the value to be tested)
            - It must return an object with three properties: 'Message', 'Value' and 'Success'.
            The Success property should be boolean and indicate whether the value is valid.
            The Value property contains the validated input. The scriptblock may legally convert the input (For example from string to int in case of integer validation)
            The message contains a string that will be passed along to an exception in case the input is NOT valid.

        .PARAMETER Name
            The name under which to register the validation scriptblock

        .PARAMETER ScriptBlock
            The scriptblock to register

        .EXAMPLE
            PS C:\> Register-DbatoolsConfigValidation -Name IntPositive -ScriptBlock $scriptBlock

            Registers the scriptblock stored in $scriptBlock as validation with the name IntPositive
       #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [ScriptBlock]
        $ScriptBlock
    )

    [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Validation[$Name.ToLowerInvariant()] = $ScriptBlock
}