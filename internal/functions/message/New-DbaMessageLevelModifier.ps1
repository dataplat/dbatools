function New-DbaMessageLevelModifier {
    <#
    .SYNOPSIS
        Allows modifying message levels by powerful filters.

    .DESCRIPTION
        Allows modifying message levels by powerful filters.

        This is designed to allow a developer to have more control over what is written how during the development process.
        It also allows a debug user to fine tune what he is shown.

        This functionality is NOT designed for default implementation within a module.
        Instead, set healthy message levels for your own messages and leave others to tend to their own levels.

        Note:
        Adding too many level modifiers may impact performance, use with discretion.

    .PARAMETER Name
        The name of the level modifier.
        Can be arbitrary, but must be unique. Not case sensitive.

    .PARAMETER Modifier
        The level modifier to apply.
        - Use a negative value to make a message more relevant
        - Use a positive value to make a message less relevant
        While not limited to this range, the original levels range from 1 through 9:
        - 1-3 : Written to host and debug by default
        - 4-6 : Written to verbose and debug by default
        - 7-9 : Internas, written only to debug

    .PARAMETER IncludeFunctionName
        Only messages from functions with one of these exact names will be considered.

    .PARAMETER ExcludeFunctionName
        Messages from functions with one of these exact names will be ignored.

    .PARAMETER IncludeModuleName
        Only messages from modules with one of these exact names will be considered.

    .PARAMETER ExcludeModuleName
        Messages from module with one of these exact names will be ignored.

    .PARAMETER IncludeTags
        Only messages that contain one of these tags will be considered.

    .PARAMETER ExcludeTags
        Messages that contain one of these tags will be ignored.

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .EXAMPLE
        PS C:\> New-DbaMessageLevelModifier -Name 'MyModule-Include' -Modifier -9 -IncludeModuleName MyModule
        PS C:\> New-DbaMessageLevelModifier -Name 'MyModule-Exclude' -Modifier 9 -ExcludeModuleName MyModule

        These settings will cause all messages from the module 'MyModule' to be highly prioritized and almost certainly written to host.
        It will also make it highly unlikely, that messages from other modules will even be considered for anything but the lowest level.

        This is useful when prioritizing your own module during development.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [int]
        $Modifier,

        [string]
        $IncludeFunctionName,

        [string]
        $ExcludeFunctionName,

        [string]
        $IncludeModuleName,

        [string]
        $ExcludeModuleName,

        [string[]]
        $IncludeTags,

        [string[]]
        $ExcludeTags,

        [switch]$EnableException
    )

    if (Test-Bound -ParameterName IncludeFunctionName, ExcludeFunctionName, IncludeModuleName, ExcludeModuleName, IncludeTags, ExcludeTags -Not) {
        Stop-Function -Message "Must specify at least one condition in order to apply message level modifier." -EnableException $EnableException -Category InvalidArgument
        return
    }

    $levelModifier = New-Object Sqlcollaborative.Dbatools.Message.MessageLevelModifier
    $levelModifier.Name = $Name.ToLowerInvariant()
    $levelModifier.Modifier = $Modifier

    if (Test-Bound -ParameterName IncludeFunctionName) {
        $levelModifier.IncludeFunctionName = $IncludeFunctionName
    }

    if (Test-Bound -ParameterName ExcludeFunctionName) {
        $levelModifier.ExcludeFunctionName = $ExcludeFunctionName
    }

    if (Test-Bound -ParameterName IncludeModuleName) {
        $levelModifier.IncludeModuleName = $IncludeModuleName
    }

    if (Test-Bound -ParameterName ExcludeModuleName) {
        $levelModifier.ExcludeModuleName = $ExcludeModuleName
    }

    if (Test-Bound -ParameterName IncludeTags) {
        $levelModifier.IncludeTags = $IncludeTags
    }

    if (Test-Bound -ParameterName ExcludeTags) {
        $levelModifier.ExcludeTags = $ExcludeTags
    }

    [Sqlcollaborative.Dbatools.Message.MessageHost]::MessageLevelModifiers[$levelModifier.Name] = $levelModifier

    $levelModifier
}