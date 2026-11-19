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

        The unfinished Write-Message frontend and message converters call the scriptblock with the relevant object as its sole input.

        Native commands use separate typed defaults. A matching caller registration, exact or conditional, makes native transformation throw NotSupportedException before applying a default, whatever the registration order; the error identifies the kind, type, function and module, and for an exception it carries the original exception as InnerException. Native commands never invoke these scripts.

        The first registration into an inactive, empty legacy registry pair seeds the defaults for that kind before adding the script. Target defaults include instance parameters and SMO servers. Exception defaults include a wildcard condition. An explicit legacy initializer seeds both kinds. Native commands ignore these library-owned defaults, including the wildcard condition, and keep using their own typed defaults.

        To remove legacy registrations, clear the corresponding MessageHost.TargetTransforms or ExceptionTransforms dictionary and remove conditions from TargetTransformList or ExceptionTransformList. Clearing an activated pair keeps the legacy frontend empty; it does not restore defaults or clear the separate native registries.

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
        if ($TargetType -or $TargetTypeFilter) {
            $targetRegistry = [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms
            $targetConditions = [Dataplat.Dbatools.Message.MessageHost]::TargetTransformList
            $hasLegacy = $targetRegistry.Count -ne 0 -or $targetConditions.GetAll().Length -ne 0
            if (-not [Dataplat.Dbatools.Message.LegacyTransformRegistryMode]::UseLegacy("Target", $targetRegistry, $targetConditions, $hasLegacy)) {
                [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register("Target")
            }
            [Dataplat.Dbatools.Message.LegacyTransformRegistryMode]::Activate("Target", $targetRegistry, $targetConditions)
        }
        if ($ExceptionType -or $ExceptionTypeFilter) {
            $exceptionRegistry = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms
            $exceptionConditions = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList
            $hasLegacy = $exceptionRegistry.Count -ne 0 -or $exceptionConditions.GetAll().Length -ne 0
            if (-not [Dataplat.Dbatools.Message.LegacyTransformRegistryMode]::UseLegacy("Exception", $exceptionRegistry, $exceptionConditions, $hasLegacy)) {
                [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register("Exception")
            }
            [Dataplat.Dbatools.Message.LegacyTransformRegistryMode]::Activate("Exception", $exceptionRegistry, $exceptionConditions)
        }
        if ($TargetType) { $targetRegistry[$TargetType.ToLowerInvariant()] = $ScriptBlock }
        if ($ExceptionType) { $exceptionRegistry[$ExceptionType.ToLowerInvariant()] = $ScriptBlock }

        if ($TargetTypeFilter) {
            $condition = New-Object Dataplat.Dbatools.Message.TransformCondition($TargetTypeFilter, $ModuleNameFilter, $FunctionNameFilter, $ScriptBlock, "Target")
            $targetConditions.Add($condition)
        }

        if ($ExceptionTypeFilter) {
            $condition = New-Object Dataplat.Dbatools.Message.TransformCondition($ExceptionTypeFilter, $ModuleNameFilter, $FunctionNameFilter, $ScriptBlock, "Exception")
            $exceptionConditions.Add($condition)
        }
    }
}
