function Register-DbaMessageEvent {
    <#
    .SYNOPSIS
        Registers an event to when a message is written.

    .DESCRIPTION
        Registers an event to when a message is written.
        These events will fire whenever the written message fulfills the specified filter criteria.

        This allows integrating direct alerts and reactions to messages as they occur.

        Warnings:
        - Adding many subscriptions can impact overall performance, even without triggering.
        - Events are executed synchronously. executing complex operations may introduce a significant delay to the command execution.

        It is recommended to push processing that involves outside resources to a separate runspace, then use the event to pass the object as trigger.
        The TaskEngine component may prove to be just what is needed to accomplish this.

    .PARAMETER Name
        The name of the subscription.
        Each subscription must have a name, subscriptions of equal name will overwrite each other.
        This is in order to avoid having runspace uses explode the number of subscriptions on each invocation.

    .PARAMETER ScriptBlock
        The scriptblock to execute.
        It will receive the message entry (as returned by Get-DbatoolsLog) as its sole argument.

    .PARAMETER MessageFilter
        Filter by message content. Understands wildcards, but not regex.

    .PARAMETER ModuleNameFilter
        Filter by Name of the module, from which the message comes. Understands wildcards, but not regex.

    .PARAMETER FunctionNameFilter
        Filter by Name of the function, from which the message comes. Understands wildcards, but not regex.

    .PARAMETER TargetFilter
        Filter by target object. Performs equality comparison on an object level.

    .PARAMETER LevelFilter
        Include only messages of the specified levels.

    .PARAMETER TagFilter
        Only include messages with any of the specified tags.

    .PARAMETER RunspaceFilter
        Only include messages which were written by the specified runspace.
        You can find out the current runspace ID by running this:
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
        You can retrieve the primary runspace - the Guid used by the runspace the user sees - by running this:
        [Sqlcollaborative.Dbatools.Utility.UtilityHost]::PrimaryRunspace

    .EXAMPLE
        PS C:\> Register-DbaMessageEvent -Name 'Mymodule.OffloadTrigger' -ScriptBlock $ScriptBlock -Tag 'engine' -Module 'MyModule' -Level Warning

        Registers an event subscription ...
        - Under the name 'Mymodule.OffloadTrigger' ...
        - To execute $ScriptBlock ...
        - Whenever a message is written with the tag 'engine' by the module 'MyModule' at the level 'Warning'
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [System.Management.Automation.ScriptBlock]
        $ScriptBlock,

        [string]
        $MessageFilter,

        [string]
        $ModuleNameFilter,

        [string]
        $FunctionNameFilter,

        $TargetFilter,

        [Sqlcollaborative.Dbatools.Message.MessageLevel[]]
        $LevelFilter,

        [string[]]
        $TagFilter,

        [System.Guid]
        $RunspaceFilter
    )

    $newName = $Name.ToLowerInvariant()
    $eventSubscription = New-Object Sqlcollaborative.Dbatools.Message.MessageEventSubscription
    $eventSubscription.Name = $newName
    $eventSubscription.ScriptBlock = $ScriptBlock

    if (Test-Bound -ParameterName MessageFilter) {
        $eventSubscription.MessageFilter = $MessageFilter
    }

    if (Test-Bound -ParameterName ModuleNameFilter) {
        $eventSubscription.ModuleNameFilter = $ModuleNameFilter
    }

    if (Test-Bound -ParameterName FunctionNameFilter) {
        $eventSubscription.FunctionNameFilter = $FunctionNameFilter
    }

    if (Test-Bound -ParameterName TargetFilter) {
        $eventSubscription.TargetFilter = $TargetFilter
    }

    if (Test-Bound -ParameterName LevelFilter) {
        $eventSubscription.LevelFilter = $LevelFilter
    }

    if (Test-Bound -ParameterName TagFilter) {
        $eventSubscription.TagFilter = $TagFilter
    }

    if (Test-Bound -ParameterName RunspaceFilter) {
        $eventSubscription.RunspaceFilter = $RunspaceFilter
    }

    [Sqlcollaborative.Dbatools.Message.MessageHost]::Events[$newName] = $eventSubscription
}