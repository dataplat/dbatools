function Convert-DbaMessageLevel {
    <#
    .SYNOPSIS
        Processes the effective message level of a message

    .DESCRIPTION
        Processes the effective message level of a message
        - Applies level decrements
        - Applies message level modifiers

    .PARAMETER OriginalLevel
        The level the message was originally written to

    .PARAMETER FromStopFunction
        Whether the message was passed through Stop-Function first.
        This is used to increment the automatic message level decrement counter by 1 (so it ignores the fact, that it was passed through Stop-Function).
        The automatic message level decrement functionality allows users to make nested commands' messages be less verbose.

    .PARAMETER Tags
        The tags that were added to the message

    .PARAMETER FunctionName
        The function that wrote the message.

    .PARAMETER ModuleName
        The module the function writing the message comes from.

    .EXAMPLE
        Convert-DbaMessageLevel -OriginalLevel $Level -FromStopFunction $fromStopFunction -Tags $Tag -FunctionName $FunctionName -ModuleName $ModuleName

        This will convert the original level of $Level based on the transformation rules for levels.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Sqlcollaborative.Dbatools.Message.MessageLevel]
        $OriginalLevel,

        [Parameter(Mandatory)]
        [bool]
        $FromStopFunction,

        [Parameter(Mandatory)]
        [AllowNull()]
        [string[]]
        $Tags,

        [Parameter(Mandatory)]
        [string]
        $FunctionName,

        [Parameter(Mandatory)]
        [string]
        $ModuleName
    )

    $number = $OriginalLevel.value__

    if ([Sqlcollaborative.Dbatools.Message.MessageHost]::NestedLevelDecrement -gt 0) {
        $depth = (Get-PSCallStack).Count - 3
        if ($FromStopFunction) { $depth = $depth - 1 }
        $number = $number + $depth * ([Sqlcollaborative.Dbatools.Message.MessageHost]::NestedLevelDecrement)
    }

    foreach ($modifier in [Sqlcollaborative.Dbatools.Message.MessageHost]::MessageLevelModifiers.Values) {
        if ($modifier.AppliesTo($FunctionName, $ModuleName, $Tags)) {
            $number = $number + $modifier.Modifier
        }
    }

    # Finalize number and return
    if ($number -lt 1) { $number = 1 }
    if ($number -gt 9) { $number = 9 }
    return ([Sqlcollaborative.Dbatools.Message.MessageLevel]$number)
}