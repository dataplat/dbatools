function Reset-DbatoolsConfig {
    <#
    .SYNOPSIS
        Resets dbatools module configuration settings back to their default values.

    .DESCRIPTION
        Restores dbatools configuration settings to their original default values, useful when troubleshooting connectivity issues, fixing misconfigured connection strings, or starting fresh after environment changes. This is particularly helpful when dbatools settings have been customized for specific environments and you need to restore the baseline behavior.

        The function can reset individual configuration items, all settings within a specific module, or all dbatools configuration settings at once. This saves you from manually tracking down and reconfiguring individual settings.

        In order for a reset to be possible, two conditions must be met:
        - The setting must have been initialized.
        - The setting cannot have been enforced by policy.

    .PARAMETER ConfigurationItem
        One or more configuration objects as returned by Get-DbatoolsConfig.
        Use this when you want to reset specific configuration items that you've already identified through Get-DbatoolsConfig, allowing for precise control over which settings get reset.

    .PARAMETER FullName
        The full qualified name of a specific configuration setting to reset (e.g., 'dbatools.Connection.EncryptConnection').
        Use this when you know the exact setting name and want to reset just that one item, providing the most precise targeting of configuration changes.

    .PARAMETER Module
        The name of the module whose configuration settings should be reset (e.g., 'dbatools', 'sql', 'connection').
        Use this when you want to reset all settings within a specific functional area, such as resetting all connection-related settings after environment changes.

    .PARAMETER Name
        A wildcard pattern to match configuration setting names within the specified module (defaults to "*" for all settings).
        Use this with the -Module parameter to selectively reset settings, such as using "Encrypt*" to reset only encryption-related settings within a module.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .OUTPUTS
        None

        This command does not return any objects to the pipeline. It performs configuration resets as a side effect. Use -WhatIf to preview what settings would be reset without making changes.

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
        [Dataplat.Dbatools.Configuration.Config[]]
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
            if ($nameItem -ceq "Dataplat.Dbatools.Configuration.Config") { continue }

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