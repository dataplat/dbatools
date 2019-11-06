function Reset-DbatoolsConfig {
    <#
    .SYNOPSIS
        Reverts a configuration item to its default value.

    .DESCRIPTION
        This command can be used to revert a configuration item to the value it was initialized with.
        Generally, this amounts to reverting it to its default value.

        In order for a reset to be possible, two conditions must be met:
        - The setting must have been initialized.
        - The setting cannot have been enforced by policy.

    .PARAMETER ConfigurationItem
        A configuration object as returned by Get-DbatoolsConfig.

    .PARAMETER FullName
        The full name of the setting to reset, offering the maximum of precision.

    .PARAMETER Module
        The name of the module, from which configurations should be reset.
        Used in conjunction with the -Name parameter to filter a specific set of items.

    .PARAMETER Name
        Used in conjunction with the -Module parameter to select which settings to reset using wildcard comparison.

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .NOTES
        Tags: Module
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Reset-DbatoolsConfig

    .EXAMPLE
        PS C:\> Reset-DbatoolsConfig -Module MyModule

        Resets all configuration items of the MyModule to default.

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig | Reset-DbatoolsConfig

        Resets ALL configuration items to default.

    .EXAMPLE
        PS C:\> Reset-DbatoolsConfig -FullName MyModule.Group.Setting1

        Resets the configuration item named 'MyModule.Group.Setting1'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline', SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [Sqlcollaborative.Dbatools.Configuration.Config[]]
        $ConfigurationItem,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [string[]]
        $FullName,

        [Parameter(Mandatory = $true, ParameterSetName = 'Module')]
        [string]
        $Module,

        [Parameter(ParameterSetName = 'Module')]
        [string]
        $Name = "*",

        [switch]$EnableException
    )

    process {
        #region By configuration Item
        foreach ($item in $ConfigurationItem) {
            if ($PSCmdlet.ShouldProcess($item.FullName, 'Reset to default value')) {
                try { $item.ResetValue() }
                catch { Stop-Function -Message "Failed to reset the configuration item." -ErrorRecord $_ -Continue -EnableException $EnableException }
            }
        }
        #endregion By configuration Item

        #region By FullName
        foreach ($nameItem in $FullName) {
            # The configuration items themselves can be cast to string, so they need to be filtered out,
            # otherwise on bind they would execute for this code-path as well.
            if ($nameItem -ceq "Sqlcollaborative.Dbatools.Configuration.Config") { continue }

            foreach ($item in (Get-DbatoolsConfig -FullName $nameItem)) {
                if ($PSCmdlet.ShouldProcess($item.FullName, 'Reset to default value')) {
                    try { $item.ResetValue() }
                    catch { Stop-Function -Message "Failed to reset the configuration item." -ErrorRecord $_ -Continue -EnableException $EnableException }
                }
            }
        }
        #endregion By FullName
        if ($Module) {
            foreach ($item in (Get-DbatoolsConfig -Module $Module -Name $Name)) {
                if ($PSCmdlet.ShouldProcess($item.FullName, 'Reset to default value')) {
                    try { $item.ResetValue() }
                    catch { Stop-Function -Message "Failed to reset the configuration item." -ErrorRecord $_ -Continue -EnableException $EnableException }
                }
            }
        }
    }
}