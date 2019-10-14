function Remove-DbaMessageLevelModifier {
    <#
    .SYNOPSIS
        Removes a message level modifier.

    .DESCRIPTION
        Removes a message level modifier.

        Message Level Modifiers can be created by using New-DbaMessageLevelModifier.
        They are used to emphasize or deemphasize messages, in order to help with debugging.

    .PARAMETER Name
        Name of the message level modifier to remove.

    .PARAMETER Modifier
        The actual modifier to remove, as returned by Get-DbaMessageLevelModifier.

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .EXAMPLE
        PS C:\> Get-DbaMessageLevelModifier | Remove-DbaMessageLevelModifier

        Removes all message level modifiers, restoring everything to their default levels.

    .EXAMPLE
        PS C:\> Remove-DbaMessageLevelModifier -Name "mymodule.foo"

        Removes the message level modifier named "mymodule.foo"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]
        $Name,

        [Parameter(ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Message.MessageLevelModifier[]]
        $Modifier,

        [switch]$EnableException
    )

    process {
        foreach ($item in $Name) {
            if ($item -eq "Sqlcollaborative.Dbatools.Message.MessageLevelModifier") { continue }

            if ([Sqlcollaborative.Dbatools.Message.MessageHost]::MessageLevelModifiers.ContainsKey($item.ToLowerInvariant())) {
                [Sqlcollaborative.Dbatools.Message.MessageHost]::MessageLevelModifiers.Remove($item.ToLowerInvariant())
            } else {
                Stop-Function -Message "No message level modifier of name $item found." -EnableException $EnableException -Category InvalidArgument -Continue
            }
        }
        foreach ($item in $Modifier) {
            if ([Sqlcollaborative.Dbatools.Message.MessageHost]::MessageLevelModifiers.ContainsKey($item.Name)) {
                [Sqlcollaborative.Dbatools.Message.MessageHost]::MessageLevelModifiers.Remove($item.Name)
            } else {
                Stop-Function -Message "No message level modifier of name $($item.Name) found." -EnableException $EnableException -Category InvalidArgument -Continue
            }
        }
    }
}