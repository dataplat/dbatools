function Register-DbaMessageTransform {
    <#
    .SYNOPSIS
        Registers a scriptblock that can transform message content.

    .DESCRIPTION
        Registers a scriptblock that can transform message content.
        This can be used to convert some kinds of input. Specifically:

        Target:
        When specifying a target, this target may require some conversion.
        For example, an object containing a live connection may need to have a static copy stored instead,
        as otherwise its export on a different runspace may cause access violations.

        Exceptions:
        Some exceptions may need transforming.
        For example some APIs might wrap the actual exception into a common wrapper.
        In this scenario you may want the actual exception in order to provide more specific information.

        In all instances, the scriptblock will be called, receiving only the relevant object as its sole input.

        Note: This transformation is performed synchronously on the active runspace. Complex scriptblocks may delay execution times when a matching object is passed.

    .PARAMETER TargetType
        The full typename of the target object to apply the scriptblock to.
        All objects of that typename will be processed through that scriptblock.

    .PARAMETER ExceptionType
        The full typename of the exception object to apply the scriptblock to.
        All objects of that typename will be processed through that scriptblock.
        Note: In case of error records, the type of the Exception Property is inspected. The error record as a whole will not be touched, except for having its exception exchanged.

    .PARAMETER ScriptBlock
        The scriptblock that performs the transformation.

    .PARAMETER TargetTypeFilter
        A filter for the typename of the target object to transform.
        Supports wildcards, but not regex.
        WARNING: Adding too many filter-type transforms may impact overall performance, try to avoid using them!

    .PARAMETER ExceptionTypeFilter
        A filter for the typename of the exception object to transform.
        Supports wildcards, but not regex.
        WARNING: Adding too many filter-type transforms may impact overall performance, try to avoid using them!

    .PARAMETER FunctionNameFilter
        Default: "*"
        Allows filtering by function name, in order to consider whether the function is affected.
        Supports wildcards, but not regex.
        WARNING: Adding too many filter-type transforms may impact overall performance, try to avoid using them!

    .PARAMETER ModuleNameFilter
        Default: "*"
        Allows filtering by module name, in order to consider whether the function is affected.
        Supports wildcards, but not regex.
        WARNING: Adding too many filter-type transforms may impact overall performance, try to avoid using them!

    .EXAMPLE
        PS C:\> Register-DbaMessageTransform -TargetType 'mymodule.category.classname' -ScriptBlock $ScriptBlock

        Whenever a target object of type 'mymodule.category.classname' is specified, invoke $ScriptBlock (with the object as sole argument) and store the result as target instead.

    .EXAMPLE
        PS C:\> Register-DbaMessageTransform -ExceptionType 'mymodule.category.exceptionname' -ScriptBlock $ScriptBlock

        Whenever an exception or error record of type 'mymodule.category.classname' is specified, invoke $ScriptBlock (with the object as sole argument) and store the result as exception instead.
        If the full error record is specified, only the updated exception will be inserted

    .EXAMPLE
        PS C:\> Register-DbaMessageTransform -TargetTypeFilter 'mymodule.category.*' -ScriptBlock $ScriptBlock

        Adds a transform for all target objects that are of a type whose full name starts with 'mymodule.category.'
        All target objects matching that typename will be run through the specified scriptblock, which in return generates the new target object.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(Mandatory, ParameterSetName = "Target")]
        [string]
        $TargetType,

        [Parameter(Mandatory, ParameterSetName = "Exception")]
        [string]
        $ExceptionType,

        [Parameter(Mandatory)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory, ParameterSetName = "TargetFilter")]
        [string]
        $TargetTypeFilter,

        [Parameter(Mandatory, ParameterSetName = "ExceptionFilter")]
        [string]
        $ExceptionTypeFilter,

        [Parameter(ParameterSetName = "TargetFilter")]
        [Parameter(ParameterSetName = "ExceptionFilter")]
        $FunctionNameFilter = "*",

        [Parameter(ParameterSetName = "TargetFilter")]
        [Parameter(ParameterSetName = "ExceptionFilter")]
        $ModuleNameFilter = "*"
    )

    process {
        if ($TargetType) { [Sqlcollaborative.Dbatools.Message.MessageHost]::TargetTransforms[$TargetType.ToLowerInvariant()] = $ScriptBlock }
        if ($ExceptionType) { [Sqlcollaborative.Dbatools.Message.MessageHost]::ExceptionTransforms[$ExceptionType.ToLowerInvariant()] = $ScriptBlock }

        if ($TargetTypeFilter) {
            $condition = New-Object Sqlcollaborative.Dbatools.Message.TransformCondition($TargetTypeFilter, $ModuleNameFilter, $FunctionNameFilter, $ScriptBlock, "Target")
            [Sqlcollaborative.Dbatools.Message.MessageHost]::TargetTransformList.Add($condition)
        }

        if ($ExceptionTypeFilter) {
            $condition = New-Object Sqlcollaborative.Dbatools.Message.TransformCondition($ExceptionTypeFilter, $ModuleNameFilter, $FunctionNameFilter, $ScriptBlock, "Exception")
            [Sqlcollaborative.Dbatools.Message.MessageHost]::ExceptionTransformList.Add($condition)
        }
    }
}