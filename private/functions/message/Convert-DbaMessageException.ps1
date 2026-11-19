function Convert-DbaMessageException {
    <#
    .SYNOPSIS
        Transforms the Exception input to the message system.

    .DESCRIPTION
        Transforms the Exception input to the message system.

        If there is an exception running a transformation scriptblock, it will log the error in the transform error queue and return the original object instead.

    .PARAMETER Exception
        The input Exception object, that might have to be transformed (may not either)

    .PARAMETER FunctionName
        The function writing the message

    .PARAMETER ModuleName
        The module, that the function writing the message is part of

    .EXAMPLE
        PS C:\> Convert-DbaMessageException -Exception $Exception -FunctionName 'Get-Test' -ModuleName 'MyModule'

        Checks internal storage for definitions that require a Exception transform, and either returns the original object or the transformed object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Exception,

        [Parameter(Mandatory)]
        [string]
        $FunctionName,

        [Parameter(Mandatory)]
        [string]
        $ModuleName
    )

    if ($null -eq $Exception) { return }

    $typeName = $Exception.GetType().FullName.ToLowerInvariant()

    $exceptionRegistry = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms
    $exceptionConditions = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList
    $hasLegacy = $exceptionRegistry.Count -ne 0 -or $exceptionConditions.GetAll().Length -ne 0
    if (-not [Dataplat.Dbatools.Message.LegacyTransformRegistryMode]::UseLegacy("Exception", $exceptionRegistry, $exceptionConditions, $hasLegacy)) {
        if ([Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransforms.ContainsKey($typeName)) {
            $nativeTransform = [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransforms[$typeName]
        } elseif ($nativeCondition = [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransformList.Get($typeName, $ModuleName, $FunctionName)) {
            $nativeTransform = $nativeCondition.Transform
        } else {
            return $Exception
        }
        try {
            $nativeResult = $null
            if ([Dataplat.Dbatools.Message.BuiltinMessageTransforms]::TryTransform($nativeTransform, $Exception, [ref]$nativeResult)) { return $nativeResult }
            return $Exception
        } catch {
            [Dataplat.Dbatools.Message.MessageHost]::WriteTransformError($_, $FunctionName, $ModuleName, $Exception, "Exception", ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            return $Exception
        }
    }

    if ($exceptionRegistry.ContainsKey($typeName)) {
        $scriptBlock = $exceptionRegistry[$typeName]
        try {
            $nativeResult = $null
            if ([Dataplat.Dbatools.Message.LegacyMessageTransforms]::TryTransform($scriptBlock, $Exception, [ref]$nativeResult)) { return $nativeResult }
            $tempException = $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create($scriptBlock.ToString())), $null, $Exception)
            return $tempException
        } catch {
            [Dataplat.Dbatools.Message.MessageHost]::WriteTransformError($_, $FunctionName, $ModuleName, $Exception, "Exception", ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            return $Exception
        }
    }

    if ($transform = $exceptionConditions.Get($typeName, $ModuleName, $FunctionName)) {
        try {
            $nativeResult = $null
            if ([Dataplat.Dbatools.Message.LegacyMessageTransforms]::TryTransform($transform.ScriptBlock, $Exception, [ref]$nativeResult)) { return $nativeResult }
            $tempException = $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create($transform.ScriptBlock.ToString())), $null, $Exception)
            return $tempException
        } catch {
            [Dataplat.Dbatools.Message.MessageHost]::WriteTransformError($_, $FunctionName, $ModuleName, $Exception, "Target", ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            return $Exception
        }
    }

    return $Exception
}
