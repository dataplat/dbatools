function Convert-DbaMessageTarget {
    <#
    .SYNOPSIS
        Transforms the target input to the message system.

    .DESCRIPTION
        Transforms the target input to the message system.

        If there is an exception running a transformation scriptblock, it will log the error in the transform error queue and return the original object instead.

    .PARAMETER Target
        The input target object, that might have to be transformed (may not either)

    .PARAMETER FunctionName
        The function writing the message

    .PARAMETER ModuleName
        The module, that the function writing the message is part of

    .EXAMPLE
        PS C:\> Convert-DbaMessageTarget -Target $Target -FunctionName 'Get-Test' -ModuleName 'MyModule'

        Checks internal storage for definitions that require a target transform, and either returns the original object or the transformed object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Target,

        [Parameter(Mandatory)]
        [string]
        $FunctionName,

        [Parameter(Mandatory)]
        [string]
        $ModuleName
    )

    if ($null -eq $Target) { return }

    $typeName = $Target.GetType().FullName.ToLowerInvariant()

    $targetRegistry = [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms
    $targetConditions = [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist
    $hasLegacy = $targetRegistry.Count -ne 0 -or $targetConditions.GetAll().Length -ne 0
    if (-not [Dataplat.Dbatools.Message.LegacyTransformRegistryMode]::UseLegacy("Target", $targetRegistry, $targetConditions, $hasLegacy)) {
        if ([Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms.ContainsKey($typeName)) {
            $nativeTransform = [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms[$typeName]
        } elseif ($nativeCondition = [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList.Get($typeName, $ModuleName, $FunctionName)) {
            $nativeTransform = $nativeCondition.Transform
        } else {
            return $Target
        }
        try {
            $nativeResult = $null
            if ([Dataplat.Dbatools.Message.BuiltinMessageTransforms]::TryTransform($nativeTransform, $Target, [ref]$nativeResult)) { return $nativeResult }
            return $Target
        } catch {
            [Dataplat.Dbatools.Message.MessageHost]::WriteTransformError($_, $FunctionName, $ModuleName, $Target, "Target", ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            return $Target
        }
    }

    if ($targetRegistry.ContainsKey($typeName)) {
        $scriptBlock = $targetRegistry[$typeName]
        try {
            $nativeResult = $null
            if ([Dataplat.Dbatools.Message.LegacyMessageTransforms]::TryTransform($scriptBlock, $Target, [ref]$nativeResult)) { return $nativeResult }
            $tempTarget = $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create($scriptBlock.ToString())), $null, $Target)
            return $tempTarget
        } catch {
            [Dataplat.Dbatools.Message.MessageHost]::WriteTransformError($_, $FunctionName, $ModuleName, $Target, "Target", ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            return $Target
        }
    }

    if ($transform = $targetConditions.Get($typeName, $ModuleName, $FunctionName)) {
        try {
            $nativeResult = $null
            if ([Dataplat.Dbatools.Message.LegacyMessageTransforms]::TryTransform($transform.ScriptBlock, $Target, [ref]$nativeResult)) { return $nativeResult }
            $tempTarget = $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create($transform.ScriptBlock.ToString())), $null, $Target)
            return $tempTarget
        } catch {
            [Dataplat.Dbatools.Message.MessageHost]::WriteTransformError($_, $FunctionName, $ModuleName, $Target, "Target", ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            return $Target
        }
    }

    return $Target
}
